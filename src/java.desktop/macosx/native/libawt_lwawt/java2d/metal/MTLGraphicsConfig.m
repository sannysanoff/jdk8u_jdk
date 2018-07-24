/*
 * Copyright (c) 2011, 2015, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#import "sun_java2d_metal_MTLGraphicsConfig.h"

#import "MTLGraphicsConfig.h"
#import "MTLSurfaceData.h"
#import "ThreadUtilities.h"

#import <stdlib.h>
#import <string.h>
#import <ApplicationServices/ApplicationServices.h>
#import <JavaNativeFoundation/JavaNativeFoundation.h>

#pragma mark -
#pragma mark "--- Mac OS X specific methods for GL pipeline ---"

/**
 * Disposes all memory and resources associated with the given
 * CGLGraphicsConfigInfo (including its native MTLContext data).
 */
void
MTLGC_DestroyMTLGraphicsConfig(jlong pConfigInfo)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLGC_DestroyMTLGraphicsConfig");

    MTLGraphicsConfigInfo *mtlinfo =
        (MTLGraphicsConfigInfo *)jlong_to_ptr(pConfigInfo);
    if (mtlinfo == NULL) {
        J2dRlsTraceLn(J2D_TRACE_ERROR,
                      "MTLGC_DestroyMTLGraphicsConfig: info is null");
        return;
    }


    MTLContext *oglc = (MTLContext*)mtlinfo->context;
    if (oglc != NULL) {
        MTLContext_DestroyContextResources(oglc);

        MTLCtxInfo *ctxinfo = (MTLCtxInfo *)oglc->ctxInfo;
        if (ctxinfo != NULL) {
            NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
            [NSOpenGLContext clearCurrentContext];
            [ctxinfo->context clearDrawable];
            [ctxinfo->context release];
            if (ctxinfo->scratchSurface != 0) {
                [ctxinfo->scratchSurface release];
            }
            [pool drain];
            free(ctxinfo);
            oglc->ctxInfo = NULL;
        }
        mtlinfo->context = NULL;
    }
    free(mtlinfo);
}

#pragma mark -
#pragma mark "--- MTLGraphicsConfig methods ---"

/**
 * This is a globally shared context used when creating textures.  When any
 * new contexts are created, they specify this context as the "share list"
 * context, which means any texture objects created when this shared context
 * is current will be available to any other context in any other thread.
 */
extern NSOpenGLContext *sharedContext;
extern NSOpenGLPixelFormat *sharedPixelFormat;

/**
 * Attempts to initialize CGL and the core OpenGL library.
 */
JNIEXPORT jboolean JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_initMTL
    (JNIEnv *env, jclass cglgc)
{
    J2dRlsTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_initMTL");
fprintf(stderr, "MTLGraphicsConfig_initMTL\n");

    if (!MTLFuncs_OpenLibrary()) {
        return JNI_FALSE;
    }

    if (!MTLFuncs_InitPlatformFuncs() ||
        !MTLFuncs_InitBaseFuncs() ||
        !MTLFuncs_InitExtFuncs())
    {
        MTLFuncs_CloseLibrary();
        return JNI_FALSE;
    }
#ifdef REMOTELAYER
    pthread_t jrsRemoteThread;
    pthread_create(&jrsRemoteThread, NULL, JRSRemoteThreadFn, NULL);
#endif

fprintf(stderr, "MTLGraphicsConfig_initMTL: OK\n");

    return JNI_TRUE;
}


/**
 * Determines whether the CGL pipeline can be used for a given GraphicsConfig
 * provided its screen number and visual ID.  If the minimum requirements are
 * met, the native CGLGraphicsConfigInfo structure is initialized for this
 * GraphicsConfig with the necessary information (pixel format, etc.)
 * and a pointer to this structure is returned as a jlong.  If
 * initialization fails at any point, zero is returned, indicating that CGL
 * cannot be used for this GraphicsConfig (we should fallback on an existing
 * 2D pipeline).
 */
JNIEXPORT jlong JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_getMTLConfigInfo
    (JNIEnv *env, jclass cglgc,
     jint displayID, jint pixfmt, jint swapInterval)
{
  jlong ret = 0L;
  JNF_COCOA_ENTER(env);
  NSMutableArray * retArray = [NSMutableArray arrayWithCapacity:3];
  [retArray addObject: [NSNumber numberWithInt: (int)displayID]];
  [retArray addObject: [NSNumber numberWithInt: (int)pixfmt]];
  [retArray addObject: [NSNumber numberWithInt: (int)swapInterval]];
  if ([NSThread isMainThread]) {
      [MTLGraphicsConfigUtil _getMTLConfigInfo: retArray];
  } else {
      [MTLGraphicsConfigUtil performSelectorOnMainThread: @selector(_getMTLConfigInfo:) withObject: retArray waitUntilDone: YES];
  }
  NSNumber * num = (NSNumber *)[retArray objectAtIndex: 0];
  ret = (jlong)[num longValue];
  JNF_COCOA_EXIT(env);
  return ret;
}



@implementation MTLGraphicsConfigUtil
+ (void) _getMTLConfigInfo: (NSMutableArray *)argValue {
    AWT_ASSERT_APPKIT_THREAD;

    jint displayID = (jint)[(NSNumber *)[argValue objectAtIndex: 0] intValue];
    jint pixfmt = (jint)[(NSNumber *)[argValue objectAtIndex: 1] intValue];
    jint swapInterval = (jint)[(NSNumber *)[argValue objectAtIndex: 2] intValue];
    JNIEnv *env = [ThreadUtilities getJNIEnvUncached];
    [argValue removeAllObjects];

    J2dRlsTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_getMTLConfigInfo");

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    CGOpenGLDisplayMask glMask = (CGOpenGLDisplayMask)pixfmt;
    if (sharedContext == NULL) {
        if (glMask == 0) {
            glMask = CGDisplayIDToOpenGLDisplayMask(displayID);
        }

        NSOpenGLPixelFormatAttribute attrs[] = {
            NSOpenGLPFAAllowOfflineRenderers,
            NSOpenGLPFAClosestPolicy,
            NSOpenGLPFAWindow,
            NSOpenGLPFAPixelBuffer,
            NSOpenGLPFADoubleBuffer,
            NSOpenGLPFAColorSize, 32,
            NSOpenGLPFAAlphaSize, 8,
            NSOpenGLPFADepthSize, 16,
            NSOpenGLPFAScreenMask, glMask,
            0
        };

        sharedPixelFormat =
            [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
        if (sharedPixelFormat == nil) {
            J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: shared NSOpenGLPixelFormat is NULL");
            [argValue addObject: [NSNumber numberWithLong: 0L]];
            return;
        }

        sharedContext =
            [[NSOpenGLContext alloc]
                initWithFormat:sharedPixelFormat
                shareContext: NULL];
        if (sharedContext == nil) {
            J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: shared NSOpenGLContext is NULL");
            [argValue addObject: [NSNumber numberWithLong: 0L]];
            return;
        }
    }

#if USE_NSVIEW_FOR_SCRATCH
    NSRect contentRect = NSMakeRect(0, 0, 64, 64);
    NSWindow *window =
        [[NSWindow alloc]
            initWithContentRect: contentRect
            styleMask: NSBorderlessWindowMask
            backing: NSBackingStoreBuffered
            defer: false];
    if (window == nil) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: NSWindow is NULL");
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }

    NSView *scratchSurface =
        [[NSView alloc]
            initWithFrame: contentRect];
    if (scratchSurface == nil) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: NSView is NULL");
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    fprintf(stderr, "USE_NSVIEW_FOR_SCRATCH");
    [window setContentView: scratchSurface];
#else
    NSOpenGLPixelBuffer *scratchSurface =
        [[NSOpenGLPixelBuffer alloc]
            initWithTextureTarget:GL_TEXTURE_2D
            textureInternalFormat:GL_RGB
            textureMaxMipMapLevel:0
            pixelsWide:64
            pixelsHigh:64];
#endif

    NSOpenGLContext *context =
        [[NSOpenGLContext alloc]
            initWithFormat: sharedPixelFormat
            shareContext: sharedContext];
    if (context == nil) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: NSOpenGLContext is NULL");
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }

    GLint contextVirtualScreen = [context currentVirtualScreen];
#if USE_NSVIEW_FOR_SCRATCH
    [context setView: scratchSurface];
#else
    [context
        setPixelBuffer: scratchSurface
        cubeMapFace:0
        mipMapLevel:0
        currentVirtualScreen: contextVirtualScreen];
#endif
    [context makeCurrentContext];

    // get version and extension strings
/*    const unsigned char *versionstr = j2d_glGetString(GL_VERSION);
    if (!MTLContext_IsVersionSupported(versionstr)) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: OpenGL 1.2 is required");
        [NSOpenGLContext clearCurrentContext];
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }*/
//    J2dRlsTraceLn1(J2D_TRACE_INFO, "MTLGraphicsConfig_getMTLConfigInfo: OpenGL version=%s", versionstr);

    jint caps = CAPS_EMPTY;
    MTLContext_GetExtensionInfo(env, &caps);

    GLint value = 0;
    [sharedPixelFormat
        getValues: &value
        forAttribute: NSOpenGLPFADoubleBuffer
        forVirtualScreen: contextVirtualScreen];
    if (value != 0) {
        caps |= CAPS_DOUBLEBUFFERED;
    }

    J2dRlsTraceLn1(J2D_TRACE_INFO,
                   "MTLGraphicsConfig_getCGLConfigInfo: db=%d",
                   (caps & CAPS_DOUBLEBUFFERED) != 0);

    // remove before shipping (?)
#if 1
    [sharedPixelFormat
        getValues: &value
        forAttribute: NSOpenGLPFAAccelerated
        forVirtualScreen: contextVirtualScreen];
    if (value == 0) {
        [sharedPixelFormat
            getValues: &value
            forAttribute: NSOpenGLPFARendererID
            forVirtualScreen: contextVirtualScreen];
        fprintf(stderr, "WARNING: GL pipe is running in software mode (Renderer ID=0x%x)\n", (int)value);
    }
#endif

    // 0: the buffers are swapped with no regard to the vertical refresh rate
    // 1: the buffers are swapped only during the vertical retrace
    GLint params = swapInterval;
    [context setValues: &params forParameter: NSOpenGLCPSwapInterval];

    MTLCtxInfo *ctxinfo = (MTLCtxInfo *)malloc(sizeof(MTLCtxInfo));
    if (ctxinfo == NULL) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGC_InitMTLContext: could not allocate memory for ctxinfo");
        [NSOpenGLContext clearCurrentContext];
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    memset(ctxinfo, 0, sizeof(MTLCtxInfo));
    ctxinfo->context = context;
    ctxinfo->scratchSurface = scratchSurface;

    MTLContext *oglc = (MTLContext *)malloc(sizeof(MTLContext));
    if (oglc == 0L) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGC_InitMTLContext: could not allocate memory for mtlc");
        [NSOpenGLContext clearCurrentContext];
        free(ctxinfo);
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    memset(oglc, 0, sizeof(MTLContext));
    oglc->ctxInfo = ctxinfo;
    oglc->caps = caps;

    // create the MTLGraphicsConfigInfo record for this config
    MTLGraphicsConfigInfo *mtlinfo = (MTLGraphicsConfigInfo *)malloc(sizeof(MTLGraphicsConfigInfo));
    if (mtlinfo == NULL) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: could not allocate memory for mtlinfo");
        [NSOpenGLContext clearCurrentContext];
        free(oglc);
        free(ctxinfo);
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    memset(mtlinfo, 0, sizeof(MTLGraphicsConfigInfo));
    mtlinfo->screen = displayID;
    mtlinfo->pixfmt = sharedPixelFormat;
    mtlinfo->context = oglc;

  //  [NSOpenGLContext clearCurrentContext];
    [argValue addObject: [NSNumber numberWithLong:ptr_to_jlong(mtlinfo)]];
    [pool drain];
}
@end //GraphicsConfigUtil

JNIEXPORT jint JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_getMTLCapabilities
    (JNIEnv *env, jclass mtlgc, jlong configInfo)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_getMTLCapabilities");

    MTLGraphicsConfigInfo *mtlinfo =
        (MTLGraphicsConfigInfo *)jlong_to_ptr(configInfo);
    if ((mtlinfo == NULL) || (mtlinfo->context == NULL)) {
        return CAPS_EMPTY;
    } else {
        return mtlinfo->context->caps;
    }
}

JNIEXPORT jint JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_nativeGetMaxTextureSize
    (JNIEnv *env, jclass mtlgc)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_nativeGetMaxTextureSize");

    __block int max = 0;

    [ThreadUtilities performOnMainThreadWaiting:YES block:^(){
        [sharedContext makeCurrentContext];
//        j2d_glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max);
        [NSOpenGLContext clearCurrentContext];
    }];

    return (jint)max;
}
