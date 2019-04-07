// Copyright 2017 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "ODModelEvaluator.h"
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

#include <sys/time.h>
#include <fstream>
#include <iostream>
#include <queue>

#include <vector>

#include "tensorflow/lite/kernels/register.h"
#include "tensorflow/lite/model.h"
#include "tensorflow/lite/op_resolver.h"
#include "tensorflow/lite/string_util.h"
#if TFLITE_USE_GPU_DELEGATE
#include "tensorflow/lite/delegates/gpu/metal_delegate.h"
#endif

#define LOG(x) std::cerr

namespace {
    
    // If you have your own model, modify this to the file name, and make sure
    // you've added the file to your app resources too.
#if TFLITE_USE_GPU_DELEGATE
    // GPU Delegate only supports float model now.
    NSString* model_file_name = @"ssd";
#else
    NSString* model_file_name = @"model_quantized";
#endif
    NSString* model_file_type = @"tflite";
    // If you have your own model, point this to the labels file.
    NSString* labels_file_name = @"model_labels";
    NSString* labels_file_type = @"txt";
    
    // These dimensions need to match those the model was trained with.
    const int wanted_input_width = 300;//224;
    const int wanted_input_height = 300;//224;
    const int wanted_input_channels = 3;
    const float input_mean = 128.0f;//127.5f;
    const float input_std = 127.5f;
    const std::string input_layer_name = "normalized_input_image_tensor";//"input";
    const std::string output_layer_name = "TFLite_Detection_PostProcess,TFLite_Detection_PostProcess:1,TFLite_Detection_PostProcess:2,TFLite_Detection_PostProcess:3";//"softmax1";
    
    NSString* FilePathForResourceName(NSString* name, NSString* extension) {
        NSString* file_path = [[NSBundle mainBundle] pathForResource:name ofType:extension];
        if (file_path == NULL) {
            LOG(FATAL) << "Couldn't find '" << [name UTF8String] << "." << [extension UTF8String]
            << "' in bundle.";
        }
        return file_path;
    }
    
    void LoadLabels(NSString* file_name, NSString* file_type, std::vector<std::string>* label_strings) {
        NSString* labels_path = FilePathForResourceName(file_name, file_type);
        if (!labels_path) {
            LOG(ERROR) << "Failed to find model proto at" << [file_name UTF8String]
            << [file_type UTF8String];
        }
        std::ifstream t;
        t.open([labels_path UTF8String]);
        std::string line;
        while (t) {
            std::getline(t, line);
            label_strings->push_back(line);
        }
        t.close();
    }
    
    // Returns the top N confidence values over threshold in the provided vector,
    // sorted by confidence in descending order.
    void GetTopN(
                 const float* prediction, const int prediction_size, const int num_results,
                 const float threshold, std::vector<std::pair<float, int> >* top_results) {
        // Will contain top N results in ascending order.
        std::priority_queue<std::pair<float, int>, std::vector<std::pair<float, int> >,
        std::greater<std::pair<float, int> > >
        top_result_pq;
        
        const long count = prediction_size;
        for (int i = 0; i < count; ++i) {
            const float value = prediction[i];
            // Only add it if it beats the threshold and has a chance at being in
            // the top N.
            if (value < threshold) {
                continue;
            }
            
            top_result_pq.push(std::pair<float, int>(value, i));
            
            // If at capacity, kick the smallest value out.
            if (top_result_pq.size() > num_results) {
                top_result_pq.pop();
            }
        }
        
        // Copy to output vector and reverse into descending order.
        while (!top_result_pq.empty()) {
            top_results->push_back(top_result_pq.top());
            top_result_pq.pop();
        }
        std::reverse(top_results->begin(), top_results->end());
    }
    
    // Preprocess the input image and feed the TFLite interpreter buffer for a float model.
    void ProcessInputWithFloatModel(
                                    uint8_t* input, float* buffer, int image_width, int image_height, int image_channels) {
        for (int y = 0; y < wanted_input_height; ++y) {
            float* out_row = buffer + (y * wanted_input_width * wanted_input_channels);
            for (int x = 0; x < wanted_input_width; ++x) {
                const int in_x = (y * image_width) / wanted_input_width;
                const int in_y = (x * image_height) / wanted_input_height;
                uint8_t* input_pixel =
                input + (in_y * image_width * image_channels) + (in_x * image_channels);
                float* out_pixel = out_row + (x * wanted_input_channels);
                for (int c = 0; c < wanted_input_channels; ++c) {
                    out_pixel[c] = (input_pixel[c] - input_mean) / input_std;
                }
            }
        }
    }
    
    // Preprocess the input image and feed the TFLite interpreter buffer for a quantized model.
    void ProcessInputWithQuantizedModel(
                                        uint8_t* input, uint8_t* output, int image_width, int image_height, int image_channels) {
        for (int y = 0; y < wanted_input_height; ++y) {
            uint8_t* out_row = output + (y * wanted_input_width * wanted_input_channels);
            for (int x = 0; x < wanted_input_width; ++x) {
                const int in_x = (y * image_width) / wanted_input_width;
                const int in_y = (x * image_height) / wanted_input_height;
                uint8_t* in_pixel = input + (in_y * image_width * image_channels) + (in_x * image_channels);
                uint8_t* out_pixel = out_row + (x * wanted_input_channels);
                for (int c = 0; c < wanted_input_channels; ++c) {
                    out_pixel[c] = in_pixel[c];
                }
            }
        }
    }
    
}  // namespace

@interface ODModelEvaluator (InternalMethods)
@end

@implementation ODModelEvaluator {
    std::vector<std::string> labels;
    std::unique_ptr<tflite::FlatBufferModel> model;
    tflite::ops::builtin::BuiltinOpResolver resolver;
    std::unique_ptr<tflite::Interpreter> interpreter;
    TfLiteDelegate* delegate;
}

- (NSMutableArray*)evaluateOnBuffer:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFRetain(pixelBuffer);
    NSMutableArray* labeledArr = [self runModelOnFrame:pixelBuffer];
    CFRelease(pixelBuffer);
    return labeledArr;
}

- (NSMutableArray*)runModelOnFrame:(CVPixelBufferRef)pixelBuffer {
    assert(pixelBuffer != NULL);
    
    OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
           sourcePixelFormat == kCVPixelFormatType_32BGRA);
    
    const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    const int image_width = (int)CVPixelBufferGetWidth(pixelBuffer);
    const int fullHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    CVPixelBufferLockFlags unlockFlags = kNilOptions;
    CVPixelBufferLockBaseAddress(pixelBuffer, unlockFlags);
    
    unsigned char* sourceBaseAddr = (unsigned char*)(CVPixelBufferGetBaseAddress(pixelBuffer));
    int image_height;
    unsigned char* sourceStartAddr;
    if (fullHeight <= image_width) {
        image_height = fullHeight;
        sourceStartAddr = sourceBaseAddr;
    } else {
        image_height = image_width;
        const int marginY = ((fullHeight - image_width) / 2);
        sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
    }
    const int image_channels = 4;
    assert(image_channels >= wanted_input_channels);
    uint8_t* in = sourceStartAddr;
    
    int input = interpreter->inputs()[0];
    TfLiteTensor *input_tensor = interpreter->tensor(input);
    
    bool is_quantized;
    switch (input_tensor->type) {
        case kTfLiteFloat32:
            is_quantized = false;
            break;
        case kTfLiteUInt8:
            is_quantized = true;
            break;
        default:
            NSLog(@"Input data type is not supported by this demo app.");
            return nil;
    }
    
    if (is_quantized) {
        uint8_t* out = interpreter->typed_tensor<uint8_t>(input);
        ProcessInputWithQuantizedModel(in, out, image_width, image_height, image_channels);
    } else {
        float* out = interpreter->typed_tensor<float>(input);
        ProcessInputWithFloatModel(in, out, image_width, image_height, image_channels);
    }
    
    double start = [[NSDate new] timeIntervalSince1970];
    if (interpreter->Invoke() != kTfLiteOk) {
        LOG(FATAL) << "Failed to invoke!";
    }
    double end = [[NSDate new] timeIntervalSince1970];
    total_latency += (end - start);
    total_count += 1;
    NSLog(@"Time: %.4lf, avg: %.4lf, count: %d", end - start, total_latency / total_count,
          total_count);
    
    
    
    
    
    // read output size from the output sensor
    const int output_tensor_index = interpreter->outputs()[2];
    
    TfLiteTensor* output_tensor = interpreter->tensor(output_tensor_index);
    TfLiteIntArray* output_dims = output_tensor->dims;
    if (output_dims->size != 2 || output_dims->data[0] != 1) {
        LOG(FATAL) << "Output of the model is in invalid format." << output_dims->size << "\n";
    }
    
    const int kNumResults = 5;
    const float kThreshold = 0.1f;
    
    std::vector<std::pair<float, int> > top_results;
    
    if (is_quantized) {
        
        uint8_t* output_boxes = interpreter->typed_output_tensor<uint8_t>(0);
        uint8_t* output_classes = interpreter->typed_output_tensor<uint8_t>(1);
        uint8_t* output_scores = interpreter->typed_output_tensor<uint8_t>(2);
        uint8_t* num_boxes = interpreter->typed_output_tensor<uint8_t>(3);
        int output_size = num_boxes[0];
        
        uint8_t* quantized_output_scores = output_scores;
        int32_t zero_point = input_tensor->params.zero_point;
        float scale = input_tensor->params.scale;
        float output[output_size];
        for (int i = 0; i < output_size; ++i) {
            output[i] = (quantized_output_scores[i] - zero_point) * scale;
        }
        GetTopN(output, output_size, kNumResults, kThreshold, &top_results);
    } else {
        
        float* output_boxes = interpreter->typed_output_tensor<float>(0);
        float* output_classes = interpreter->typed_output_tensor<float>(1);
        float* output_scores = interpreter->typed_output_tensor<float>(2);
        float* num_boxes = interpreter->typed_output_tensor<float>(3);
        
        const int output_size = num_boxes[0];
        
        GetTopN(output_scores, output_size, kNumResults, kThreshold, &top_results);
        
        
        NSLog(@"\nnum_boxes: %d \n", output_size);
        
        const int input_img_width = (int)CVPixelBufferGetWidth(pixelBuffer);
        const int input_img_height = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        NSMutableArray* output_values = [[NSMutableArray alloc] init];
        for (const auto& result : top_results) {
            const int index = result.second;
            NSNumber* obj_class = [NSNumber numberWithInt:output_classes[index]];
            NSNumber* confidence = [NSNumber numberWithFloat:result.first];//output_scores[index]
            NSNumber* ymin = [NSNumber numberWithFloat:output_boxes[index * 4]];
            NSNumber* xmin = [NSNumber numberWithFloat:output_boxes[index * 4 + 1]];
            NSNumber* ymax = [NSNumber numberWithFloat:output_boxes[index * 4 + 2]];
            NSNumber* xmax = [NSNumber numberWithFloat:output_boxes[index * 4 + 3]];
            
            id objects[] = { obj_class, confidence, ymin, xmin, ymax, xmax };
            id keys[] = { @"obj_class", @"confidence", @"ymin", @"xmin", @"ymax", @"xmax" };
            NSUInteger count = sizeof(objects) / sizeof(id);
            NSDictionary *dictionary = [NSDictionary dictionaryWithObjects:objects
                                                                   forKeys:keys
                                                                     count:count];
            [output_values addObject:dictionary];
            
            //NSLog(@"\nbox%d is at: %f, %f, %f, %f", index, output_boxes[index * 4], output_boxes[index * 4 + 1], output_boxes[index * 4 + 2], output_boxes[index * 4 + 3]);
            //NSLog(@"\nbox%d is at: %f, %f, %f, %f", index, obj_class, confidence, output_classes[index], result.first);
        }
        
        return output_values;
    }
    
    
    
    return NULL;
    float* output_boxes = interpreter->typed_output_tensor<float>(0);
    float* output_classes = interpreter->typed_output_tensor<float>(1);
    float* output_scores = interpreter->typed_output_tensor<float>(2);
    float* num_boxes = interpreter->typed_output_tensor<float>(3);
    
    NSMutableDictionary* newValues = [NSMutableDictionary dictionary];
    for (const auto& result : top_results) {
        const float confidence = result.first;
        const int index = result.second;
        NSString* labelObject = [NSString stringWithUTF8String:labels[output_classes[index]].c_str()];
        NSNumber* valueObject = [NSNumber numberWithFloat:confidence];
        [newValues setObject:valueObject forKey:labelObject];
    }
    NSArray* sortedLabels = [self setPredictionValues:newValues];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, unlockFlags);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return sortedLabels;
}

- (NSArray*)setPredictionValues:(NSDictionary*)newValues {
    const float decayValue = 0.75f;
    const float updateValue = 0.25f;
    const float minimumThreshold = 0.01f;
    
    NSMutableDictionary* decayedPredictionValues = [[NSMutableDictionary alloc] init];
    for (NSString* label in oldPredictionValues) {
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float decayedPredictionValue = (oldPredictionValue * decayValue);
        if (decayedPredictionValue > minimumThreshold) {
            NSNumber* decayedPredictionValueObject = [NSNumber numberWithFloat:decayedPredictionValue];
            [decayedPredictionValues setObject:decayedPredictionValueObject forKey:label];
        }
    }
    oldPredictionValues = decayedPredictionValues;
    
    for (NSString* label in newValues) {
        NSNumber* newPredictionValueObject = [newValues objectForKey:label];
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        if (!oldPredictionValueObject) {
            oldPredictionValueObject = [NSNumber numberWithFloat:0.0f];
        }
        const float newPredictionValue = [newPredictionValueObject floatValue];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float updatedPredictionValue = (oldPredictionValue + (newPredictionValue * updateValue));
        NSNumber* updatedPredictionValueObject = [NSNumber numberWithFloat:updatedPredictionValue];
        [oldPredictionValues setObject:updatedPredictionValueObject forKey:label];
    }
    NSArray* candidateLabels = [NSMutableArray array];
    for (NSString* label in oldPredictionValues) {
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        if (oldPredictionValue > 0.05f) {
            NSDictionary* entry = @{@"label" : label, @"value" : oldPredictionValueObject};
            candidateLabels = [candidateLabels arrayByAddingObject:entry];
        }
    }
    NSSortDescriptor* sort = [NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO];
    NSArray* sortedLabels =
    [candidateLabels sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];
    
    return sortedLabels;
}

- (void)freeModel {
#if TFLITE_USE_GPU_DELEGATE
    if (delegate) {
        DeleteGpuDelegate(delegate);
    }
#endif
}

- (void)loadModel {
    oldPredictionValues = [[NSMutableDictionary alloc] init];
    
    NSString* graph_path = FilePathForResourceName(model_file_name, model_file_type);
    model = tflite::FlatBufferModel::BuildFromFile([graph_path UTF8String]);
    if (!model) {
        LOG(FATAL) << "Failed to mmap model " << graph_path;
    }
    LOG(INFO) << "Loaded model " << graph_path;
    model->error_reporter();
    LOG(INFO) << "resolved reporter";
    
    tflite::ops::builtin::BuiltinOpResolver resolver;
    LoadLabels(labels_file_name, labels_file_type, &labels);
    
    tflite::InterpreterBuilder(*model, resolver)(&interpreter);
    
#if TFLITE_USE_GPU_DELEGATE
    GpuDelegateOptions options;
    options.allow_precision_loss = true;
    options.wait_type = GpuDelegateOptions::WaitType::kActive;
    delegate = NewGpuDelegate(&options);
    interpreter->ModifyGraphWithDelegate(delegate);
#endif
    
    // Explicitly resize the input tensor.
    {
        int input = interpreter->inputs()[0];
        std::vector<int> sizes = {1, 224, 224, 3};
        interpreter->ResizeInputTensor(input, sizes);
    }
    if (!interpreter) {
        LOG(FATAL) << "Failed to construct interpreter";
    }
    if (interpreter->AllocateTensors() != kTfLiteOk) {
        LOG(FATAL) << "Failed to allocate tensors!";
    }
}

@end
