#import "MTLGraphicsConfig.h"
#import "MTLLayer.h"
#import "ThreadUtilities.h"
#import "LWCToolkit.h"
#import "MTLSurfaceData.h"


extern NSOpenGLPixelFormat *sharedPixelFormat;
extern NSOpenGLContext *sharedContext;

const int N = 2;
static struct Vertex verts[N*3];

@implementation MTLLayer {
@public
    dispatch_semaphore_t _semaphore;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer> _vertexBuffer;
    id<CAMetalDrawable> _currentDrawable;
    BOOL _layerSizeDidUpdate;
    id<MTLLibrary> _library;
    id<MTLDevice> 			    _device;
    id <MTLBuffer> _uniformBuffer;
    int uniformBufferIndex;
    id <MTLCommandBuffer> _commandBuffer;
    struct FrameUniforms * _uniforms;
    BOOL _emptyCommandBuffer;
}

@synthesize javaLayer;
@synthesize textureID;
@synthesize target;
@synthesize textureWidth;
@synthesize textureHeight;

- (id) initWithJavaLayer:(JNFWeakJObjectWrapper *)layer;
{
fprintf(stderr, "MTLayer.initWithJavaLayer\n");
AWT_ASSERT_APPKIT_THREAD;
    // Initialize ourselves
    self = [super init];
    if (self == nil) return self;

    self.javaLayer = layer;

    self.contentsGravity = kCAGravityTopLeft;

    //Disable CALayer's default animation
    NSMutableDictionary * actions = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                    [NSNull null], @"anchorPoint",
                                    [NSNull null], @"bounds",
                                    [NSNull null], @"contents",
                                    [NSNull null], @"contentsScale",
                                    [NSNull null], @"onOrderIn",
                                    [NSNull null], @"onOrderOut",
                                    [NSNull null], @"position",
                                    [NSNull null], @"sublayers",
                                    nil];
    self.actions = actions;
    [actions release];

    textureID = 0; // texture will be created by rendering pipe
    target = 0;

    _device = MTLCreateSystemDefaultDevice();
    self.device          = _device;
    NSError *error = nil;
    _library = [_device newLibraryWithFile: @"/Users/avu/export/jdk8u.git/build/macosx-x86_64-normal-server-release/images/jdk-bundle/jdk-9.0.1.jdk/Contents/Home/lib/shaders.metallib" error:&error];
    if (!_library) {
        NSLog(@"Failed to load library. error %@", error);
        exit(0);
    }
    id <MTLFunction> vertFunc = [_library newFunctionWithName:@"vert"];
    id <MTLFunction> fragFunc = [_library newFunctionWithName:@"frag"];

    // Create depth state.
    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;

    MTLVertexDescriptor *vertDesc = [MTLVertexDescriptor new];
    vertDesc.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    vertDesc.attributes[VertexAttributePosition].offset = 0;
    vertDesc.attributes[VertexAttributePosition].bufferIndex = MeshVertexBuffer;
    vertDesc.attributes[VertexAttributeColor].format = MTLVertexFormatUChar4;
    vertDesc.attributes[VertexAttributeColor].offset = 3*sizeof(float);
    vertDesc.attributes[VertexAttributeColor].bufferIndex = MeshVertexBuffer;
    vertDesc.layouts[MeshVertexBuffer].stride = sizeof(struct Vertex);
    vertDesc.layouts[MeshVertexBuffer].stepRate = 1;
    vertDesc.layouts[MeshVertexBuffer].stepFunction = MTLVertexStepFunctionPerVertex;

    // Create pipeline state.
    MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
    pipelineDesc.sampleCount = 1;
    pipelineDesc.vertexFunction = vertFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    pipelineDesc.vertexDescriptor = vertDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state, error %@", error);
        exit(0);
    }


    verts[0].position[0] = 0;
    verts[0].position[1] = 0;
    verts[0].position[2] = 0;

    verts[1].position[0] = 1;
    verts[1].position[1] = 0;
    verts[1].position[2] = 0;

    verts[2].position[0] = 1;
    verts[2].position[1] = 1;
    verts[2].position[2] = 0;

    verts[0].color[0] = 255;
    verts[0].color[1] = 0;
    verts[0].color[2] = 255;
    verts[0].color[3] = 255;

    verts[1].color[0] = 255;
    verts[1].color[1] = 255;
    verts[1].color[2] = 0;
    verts[1].color[3] = 255;

    verts[2].color[0] = 255;
    verts[2].color[1] = 255;
    verts[2].color[2] = 255;
    verts[2].color[3] = 0;

    _vertexBuffer = [_device newBufferWithBytes:verts
                                             length:sizeof(verts)
                                            options:
                                                    MTLResourceCPUCacheModeDefaultCache];

    _uniformBuffer = [_device newBufferWithLength:sizeof(struct FrameUniforms)
                                          options:MTLResourceCPUCacheModeWriteCombined];

   _semaphore = dispatch_semaphore_create(2);
    uniformBufferIndex = 0;

    // Create command queue
    _commandQueue = [_device newCommandQueue];
    _commandBuffer = nil;
    _emptyCommandBuffer = YES;
    return self;
}

- (void) fillParallelogramX:(jfloat)x
                          Y:(jfloat)y
                        DX1:(jfloat)dx1
                        DY1:(jfloat)dy1
                        DX2:(jfloat)dx2
                        DY2:(jfloat)dy2
{
    if (!_commandBuffer) {
        [self beginFrame];
    }
    _emptyCommandBuffer = NO;
    fprintf(stderr, "----fillParallelogramX----\n");

    verts[0].position[0] = (2.0*x/self.drawableSize.width) - 1.0;
    verts[0].position[1] = 2.0*(1.0 - y/self.drawableSize.height) - 1.0;
    verts[0].position[2] = 0;

    verts[1].position[0] = 2.0*(x+dx1)/self.drawableSize.width - 1.0;
    verts[1].position[1] = 2.0*(1.0 - (y+dy1)/self.drawableSize.height) - 1.0;
    verts[1].position[2] = 0;

    verts[2].position[0] = 2.0*(x+dx2)/self.drawableSize.width - 1.0;
    verts[2].position[1] = 2.0*(1.0 - (y+dy2)/self.drawableSize.height) - 1.0;
    verts[2].position[2] = 0;

    verts[3].position[0] = 2.0*(x+dx1)/self.drawableSize.width - 1.0;
    verts[3].position[1] = 2.0*(1.0 - (y+dy1)/self.drawableSize.height) - 1.0;
    verts[3].position[2] = 0;

    verts[4].position[0] = 2.0*(x + dx1 + dx2)/self.drawableSize.width - 1.0;
    verts[4].position[1] = 2.0*(1.0 - (y+ dy1 + dy2)/self.drawableSize.height) - 1.0;
    verts[4].position[2] = 0;

    verts[5].position[0] = 2.0*(x+dx2)/self.drawableSize.width - 1.0;
    verts[5].position[1] = 2.0*(1.0 - (y+dy2)/self.drawableSize.height) - 1.0;
    verts[5].position[2] = 0;

    verts[0].color[0] = 255;
    verts[0].color[1] = 0;
    verts[0].color[2] = 255;
    verts[0].color[3] = 255;

    verts[1].color[0] = 255;
    verts[1].color[1] = 255;
    verts[1].color[2] = 0;
    verts[1].color[3] = 255;

    verts[2].color[0] = 255;
    verts[2].color[1] = 255;
    verts[2].color[2] = 255;
    verts[2].color[3] = 0;

    verts[3].color[0] = 255;
    verts[3].color[1] = 0;
    verts[3].color[2] = 255;
    verts[3].color[3] = 255;

    verts[4].color[0] = 255;
    verts[4].color[1] = 255;
    verts[4].color[2] = 0;
    verts[4].color[3] = 255;

    verts[5].color[0] = 255;
    verts[5].color[1] = 255;
    verts[5].color[2] = 255;
    verts[5].color[3] = 0;


    _vertexBuffer = [_device newBufferWithBytes:verts
                                         length:sizeof(verts)
                                        options:
                                                MTLResourceCPUCacheModeDefaultCache];
    // Encode render command.
    MTLRenderPassDescriptor*  _renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];

    if (_renderPassDesc) {
        MTLRenderPassColorAttachmentDescriptor *colorAttachment = _renderPassDesc.colorAttachments[0];
        colorAttachment.texture = _currentDrawable.texture;
        colorAttachment.loadAction = MTLLoadActionLoad;
        colorAttachment.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);

        colorAttachment.storeAction = MTLStoreActionStore;
        id <MTLRenderCommandEncoder> encoder =
                [_commandBuffer renderCommandEncoderWithDescriptor:_renderPassDesc];
        MTLViewport vp = {0, 0, self.drawableSize.width, self.drawableSize.height, 0, 1};
        //fprintf(stderr, "%f %f \n", self.drawableSize.width, self.drawableSize.height);
        [encoder setViewport:vp];
        [encoder setRenderPipelineState:_pipelineState];
        [encoder setVertexBuffer:_uniformBuffer
                          offset:0 atIndex:FrameUniformBuffer];

        [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:MeshVertexBuffer];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:N * 3];
        [encoder endEncoding];
    }

}
- (void) beginFrame {
    if (_commandBuffer) {
        [self endFrame];
    }
    fprintf(stderr, "----beginFrame----\n");
//    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (!_currentDrawable) {
        _currentDrawable = [[self nextDrawable] retain];
    }

    if (!_currentDrawable) {
        fprintf(stderr, "ERROR: Failed to get a valid drawable.\n");
    } else {
        vector_float4 X = {1, 0, 0, 0};
        vector_float4 Y = {0, 1, 0, 0};
        vector_float4 Z = {0, 0, 1, 0};
        vector_float4 W = {0, 0, 0, 1};

        matrix_float4x4 rot = {X, Y, Z, W};

        _uniforms = (struct FrameUniforms *) [_uniformBuffer contents];
        _uniforms->projectionViewModel = rot;

        // Create a command buffer.
        _commandBuffer = [[_commandQueue commandBuffer] retain];
    }

}

- (void) endFrame {

    if (_commandBuffer) {
        fprintf(stderr, "----endFrame----\n");

//        __block dispatch_semaphore_t semaphore = _semaphore;
//        [_commandBuffer addCompletedHandler:^(id <MTLCommandBuffer> buffer) {
//            [_commandBuffer release];
//            if (_currentDrawable) [_currentDrawable release];
//            _commandBuffer = nil;
//            dispatch_semaphore_signal(semaphore);
//
//        }];
        if (!_emptyCommandBuffer) {
            [_commandBuffer presentDrawable:_currentDrawable];
            [_commandBuffer commit];
        }


        [_commandBuffer release];
        if (_currentDrawable) [_currentDrawable release];
        _currentDrawable = nil;
        _commandBuffer = nil;
        _emptyCommandBuffer = YES;
        fprintf(stderr, "----endFrame---- 1\n");
    }
}

- (void) dealloc {
    self.javaLayer = nil;
    [super dealloc];
}
/*
- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask {
    return CGLRetainPixelFormat(sharedPixelFormat.CGLPixelFormatObj);
}

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pixelFormat {
    CGLContextObj contextObj = NULL;
    CGLCreateContext(pixelFormat, sharedContext.CGLContextObj, &contextObj);
    return contextObj;
}
*/
// use texture (intermediate buffer) as src and blit it to the layer
- (void) blitTexture
{
    if (textureID == 0) {
        return;
    }
/*
    glEnable(target);
    glBindTexture(target, textureID);

    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE); // srccopy

    float swid = 1.0f, shgt = 1.0f;
    if (target == GL_TEXTURE_RECTANGLE_ARB) {
        swid = textureWidth;
        shgt = textureHeight;
    }
    glBegin(GL_QUADS);
    glTexCoord2f(0.0f, 0.0f); glVertex2f(-1.0f, -1.0f);
    glTexCoord2f(swid, 0.0f); glVertex2f( 1.0f, -1.0f);
    glTexCoord2f(swid, shgt); glVertex2f( 1.0f,  1.0f);
    glTexCoord2f(0.0f, shgt); glVertex2f(-1.0f,  1.0f);
    glEnd();

    glBindTexture(target, 0);
    glDisable(target);
    */
}

-(void)draw
{
    fprintf(stderr, "MTLayer.draw\n");
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (!_currentDrawable) {
        _currentDrawable = [self nextDrawable];
    }

    if (!_currentDrawable) {
            fprintf(stderr, "ERROR: Failed to get a valid drawable.\n");
    } else {
        vector_float4 X = { 1, 0, 0, 0 };
        vector_float4 Y = { 0, 1, 0, 0 };
        vector_float4 Z = { 0, 0, 1, 0 };
        vector_float4 W = { 0, 0, 0, 1 };

        matrix_float4x4 rot = { X, Y, Z, W };

        struct FrameUniforms *uniforms = (struct FrameUniforms *) [_uniformBuffer contents];
        uniforms->projectionViewModel = rot;

        // Create a command buffer.
        id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

        // Encode render command.
          MTLRenderPassDescriptor*  _renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];

        if (_renderPassDesc) {
            MTLRenderPassColorAttachmentDescriptor *colorAttachment = _renderPassDesc.colorAttachments[0];
            colorAttachment.texture = _currentDrawable.texture;
            colorAttachment.loadAction = MTLLoadActionClear;
            colorAttachment.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);

            colorAttachment.storeAction = MTLStoreActionStore;
            id <MTLRenderCommandEncoder> encoder =
                [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDesc];
            MTLViewport vp = {0, 0, self.drawableSize.width, self.drawableSize.height, 0, 1};
            //fprintf(stderr, "%f %f \n", self.drawableSize.width, self.drawableSize.height);
            [encoder setViewport:vp];
            [encoder setRenderPipelineState:_pipelineState];
            [encoder setVertexBuffer:_uniformBuffer
                          offset:0 atIndex:FrameUniformBuffer];

            [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:MeshVertexBuffer];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:N*3];
            [encoder endEncoding];


            // Set callback for semaphore.
            __block dispatch_semaphore_t semaphore = _semaphore;
            [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
                dispatch_semaphore_signal(semaphore);
            }];
            [commandBuffer presentDrawable:_currentDrawable];
            [commandBuffer commit];
        }
    }
    _currentDrawable = nil;
/*
    AWT_ASSERT_APPKIT_THREAD;

    JNIEnv *env = [ThreadUtilities getJNIEnv];
    static JNF_CLASS_CACHE(jc_JavaLayer, "sun/java2d/metal/MTLLayer");
    static JNF_MEMBER_CACHE(jm_drawInCGLContext, jc_JavaLayer, "drawInCGLContext", "()V");

    jobject javaLayerLocalRef = [self.javaLayer jObjectWithEnv:env];
    if ((*env)->IsSameObject(env, javaLayerLocalRef, NULL)) {
        return;
    }

    // Set the current context to the one given to us.
    CGLSetCurrentContext(glContext);

    // Should clear the whole CALayer, because it can be larger than our texture.
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);

    glViewport(0, 0, textureWidth, textureHeight);

    JNFCallVoidMethod(env, javaLayerLocalRef, jm_drawInCGLContext);
    (*env)->DeleteLocalRef(env, javaLayerLocalRef);

    // Call super to finalize the drawing. By default all it does is call glFlush().
//    [super drawInCGLContext:glContext pixelFormat:pixelFormat forLayerTime:timeInterval displayTime:timeStamp];

    CGLSetCurrentContext(NULL);
    */
}

@end

/*
 * Class:     sun_java2d_metal_CGLLayer
 * Method:    nativeCreateLayer
 * Signature: ()J
 */
JNIEXPORT jlong JNICALL
Java_sun_java2d_metal_MTLLayer_nativeCreateLayer
(JNIEnv *env, jobject obj)
{
    __block MTLLayer *layer = nil;

JNF_COCOA_ENTER(env);

    JNFWeakJObjectWrapper *javaLayer = [JNFWeakJObjectWrapper wrapperWithJObject:obj withEnv:env];

    [ThreadUtilities performOnMainThreadWaiting:YES block:^(){
            AWT_ASSERT_APPKIT_THREAD;
        
            layer = [[MTLLayer alloc] initWithJavaLayer: javaLayer];
    }];
    
JNF_COCOA_EXIT(env);

    return ptr_to_jlong(layer);
}

// Must be called under the RQ lock.
JNIEXPORT void JNICALL
Java_sun_java2d_metal_MTLLayer_validate
(JNIEnv *env, jclass cls, jlong layerPtr, jobject surfaceData)
{
    MTLLayer *layer = OBJC(layerPtr);
fprintf(stderr, "Java_sun_java2d_metal_MTLLayer_validate\n");
    if (surfaceData != NULL) {
        BMTLSDOps *oglsdo = (BMTLSDOps*) SurfaceData_GetOps(env, surfaceData);
        layer.textureID = oglsdo->textureID;
        //layer.target =  GL_TEXTURE_2D;
        layer.textureWidth = oglsdo->width;
        layer.textureHeight = oglsdo->height;
    } else {
        layer.textureID = 0;
    }
}

// Must be called on the AppKit thread and under the RQ lock.
JNIEXPORT void JNICALL
Java_sun_java2d_metal_MTLLayer_blitTexture
(JNIEnv *env, jclass cls, jlong layerPtr)
{
    fprintf(stderr, "Blit!!!\n");
    MTLLayer *layer = jlong_to_ptr(layerPtr);

    [layer blitTexture];
}

JNIEXPORT void JNICALL
Java_sun_java2d_metal_MTLLayer_nativeSetScale
(JNIEnv *env, jclass cls, jlong layerPtr, jdouble scale)
{
    JNF_COCOA_ENTER(env);
    MTLLayer *layer = jlong_to_ptr(layerPtr);
    // We always call all setXX methods asynchronously, exception is only in 
    // this method where we need to change native texture size and layer's scale
    // in one call on appkit, otherwise we'll get window's contents blinking, 
    // during screen-2-screen moving.
    [ThreadUtilities performOnMainThreadWaiting:[NSThread isMainThread] block:^(){
        layer.contentsScale = scale;
    }];
    JNF_COCOA_EXIT(env);
}
