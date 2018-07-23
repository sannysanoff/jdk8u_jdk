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

#import <stdlib.h>

#import "sun_java2d_metal_MTLSurfaceData.h"

#import "jni_util.h"
#import "MTLRenderQueue.h"
#import "MTLGraphicsConfig.h"
#import "MTLSurfaceData.h"
#import "ThreadUtilities.h"

/* JDK's glext.h is already included and will prevent the Apple glext.h
 * being included, so define the externs directly
 */
extern void glBindFramebufferEXT(GLenum target, GLuint framebuffer);
extern CGLError CGLTexImageIOSurface2D(
        CGLContextObj ctx, GLenum target, GLenum internal_format,
        GLsizei width, GLsizei height, GLenum format, GLenum type,
        IOSurfaceRef ioSurface, GLuint plane);

/**
 * The methods in this file implement the native windowing system specific
 * layer (CGL) for the OpenGL-based Java 2D pipeline.
 */

#pragma mark -
#pragma mark "--- Mac OS X specific methods for GL pipeline ---"

// TODO: hack that's called from OGLRenderQueue to test out unlockFocus behavior
#if 0
void
OGLSD_UnlockFocus(OGLContext *oglc, OGLSDOps *dstOps)
{
    CGLCtxInfo *ctxinfo = (CGLCtxInfo *)oglc->ctxInfo;
    CGLSDOps *cglsdo = (CGLSDOps *)dstOps->privOps;
    fprintf(stderr, "about to unlock focus: %p %p\n",
            cglsdo->peerData, ctxinfo->context);

    NSOpenGLView *nsView = cglsdo->peerData;
    if (nsView != NULL) {
JNF_COCOA_ENTER(env);
        [nsView unlockFocus];
JNF_COCOA_EXIT(env);
    }
}
#endif

/**
 * Makes the given context current to its associated "scratch" surface.  If
 * the operation is successful, this method will return JNI_TRUE; otherwise,
 * returns JNI_FALSE.
 */
static jboolean
MTLSD_MakeCurrentToScratch(JNIEnv *env, MTLContext *oglc)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLSD_MakeCurrentToScratch");
    return JNI_TRUE;
}

/**
 * This function disposes of any native windowing system resources associated
 * with this surface.
 */
void
MTLSD_DestroyMTLSurface(JNIEnv *env, MTLSDOps *mtlsdo)
{
    J2dTraceLn(J2D_TRACE_INFO, "OGLSD_DestroyOGLSurface");
}

/**
 * Returns a pointer (as a jlong) to the native CGLGraphicsConfigInfo
 * associated with the given OGLSDOps.  This method can be called from
 * shared code to retrieve the native GraphicsConfig data in a platform-
 * independent manner.
 */
jlong
MTLSD_GetNativeConfigInfo(BMTLSDOps *oglsdo)
{
    J2dTraceLn(J2D_TRACE_INFO, "OGLSD_GetNativeConfigInfo");

    return 0;
}

/**
 * Makes the given GraphicsConfig's context current to its associated
 * "scratch" surface.  If there is a problem making the context current,
 * this method will return NULL; otherwise, returns a pointer to the
 * OGLContext that is associated with the given GraphicsConfig.
 */
void *
MTLSD_SetScratchSurface(JNIEnv *env, jlong pConfigInfo)
{
    J2dTraceLn(J2D_TRACE_INFO, "OGLSD_SetScratchContext");

    return NULL;
}

/**
 * Makes a context current to the given source and destination
 * surfaces.  If there is a problem making the context current, this method
 * will return NULL; otherwise, returns a pointer to the OGLContext that is
 * associated with the destination surface.
 */
MTLContext *
MTLSD_MakeOGLContextCurrent(JNIEnv *env, MTLSDOps *srcOps, MTLSDOps *dstOps)
{
    J2dTraceLn(J2D_TRACE_INFO, "OGLSD_MakeOGLContextCurrent");


    return NULL;
}

/**
 * This function initializes a native window surface and caches the window
 * bounds in the given OGLSDOps.  Returns JNI_TRUE if the operation was
 * successful; JNI_FALSE otherwise.
 */
jboolean
MTLSD_InitOGLWindow(JNIEnv *env, MTLSDOps *oglsdo)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLSD_InitOGLWindow");

    return JNI_TRUE;
}

void
MTLSD_SwapBuffers(JNIEnv *env, jlong pPeerData)
{
    J2dTraceLn(J2D_TRACE_INFO, "OGLSD_SwapBuffers");
}

void
MTLSD_Flush(JNIEnv *env)
{
    BMTLSDOps *dstOps = MTLRenderQueue_GetCurrentDestination();
    if (dstOps != NULL) {
        MTLSDOps *dstCGLOps = (MTLSDOps *)dstOps->privOps;
        MTLLayer *layer = (MTLLayer*)dstCGLOps->layer;
        if (layer != NULL) {
            [JNFRunLoop performOnMainThreadWaiting:NO withBlock:^(){
                AWT_ASSERT_APPKIT_THREAD;
                [layer draw];
            }];
        }
    }
}

#pragma mark -
#pragma mark "--- CGLSurfaceData methods ---"

extern LockFunc        MTLSD_Lock;
extern GetRasInfoFunc  MTLSD_GetRasInfo;
extern UnlockFunc      MTLSD_Unlock;


JNIEXPORT void JNICALL
Java_sun_java2d_metal_MTLSurfaceData_initOps
    (JNIEnv *env, jobject cglsd,
     jlong pConfigInfo, jlong pPeerData, jlong layerPtr,
     jint xoff, jint yoff, jboolean isOpaque)
{
    J2dTraceLn(J2D_TRACE_INFO, "CGLSurfaceData_initOps");
    J2dTraceLn1(J2D_TRACE_INFO, "  pPeerData=%p", jlong_to_ptr(pPeerData));
    J2dTraceLn2(J2D_TRACE_INFO, "  xoff=%d, yoff=%d", (int)xoff, (int)yoff);

    BMTLSDOps *bmtlsdo = (MTLSDOps *)
        SurfaceData_InitOps(env, cglsd, sizeof(MTLSDOps));
    MTLSDOps *mtlsdo = (MTLSDOps *)malloc(sizeof(MTLSDOps));
    if (mtlsdo == NULL) {
        JNU_ThrowOutOfMemoryError(env, "creating native cgl ops");
        return;
    }

    bmtlsdo->privOps = mtlsdo;

    bmtlsdo->sdOps.Lock               = MTLSD_Lock;
    bmtlsdo->sdOps.GetRasInfo         = MTLSD_GetRasInfo;
    bmtlsdo->sdOps.Unlock             = MTLSD_Unlock;
    bmtlsdo->sdOps.Dispose            = MTLSD_Dispose;

    bmtlsdo->drawableType = MTLSD_UNDEFINED;
    //bmtlsdo->activeBuffer = GL_FRONT;
    bmtlsdo->needsInit = JNI_TRUE;
    bmtlsdo->xOffset = xoff;
    bmtlsdo->yOffset = yoff;
    bmtlsdo->isOpaque = isOpaque;

    mtlsdo->peerData = (AWTView *)jlong_to_ptr(pPeerData);
    mtlsdo->layer = (MTLLayer *)jlong_to_ptr(layerPtr);
    mtlsdo->configInfo = (MTLGraphicsConfigInfo *)jlong_to_ptr(pConfigInfo);

    if (mtlsdo->configInfo == NULL) {
        free(mtlsdo);
        JNU_ThrowNullPointerException(env, "Config info is null in initOps");
    }
}

JNIEXPORT void JNICALL
Java_sun_java2d_metal_MTLSurfaceData_clearWindow
(JNIEnv *env, jobject cglsd)
{
    J2dTraceLn(J2D_TRACE_INFO, "CGLSurfaceData_clearWindow");

    BMTLSDOps *mtlsdo = (MTLSDOps*) SurfaceData_GetOps(env, cglsd);
    MTLSDOps *cglsdo = (MTLSDOps*) mtlsdo->privOps;

    cglsdo->peerData = NULL;
    cglsdo->layer = NULL;
}

#pragma mark -
#pragma mark "--- CGLSurfaceData methods - Mac OS X specific ---"

// Must be called on the QFT...
JNIEXPORT void JNICALL
Java_sun_java2d_metal_MTLSurfaceData_validate
    (JNIEnv *env, jobject jsurfacedata,
     jint xoff, jint yoff, jint width, jint height, jboolean isOpaque)
{
    J2dTraceLn2(J2D_TRACE_INFO, "CGLSurfaceData_validate: w=%d h=%d", width, height);

    BMTLSDOps *mtlsdo = (BMTLSDOps*)SurfaceData_GetOps(env, jsurfacedata);
    mtlsdo->needsInit = JNI_TRUE;
    mtlsdo->xOffset = xoff;
    mtlsdo->yOffset = yoff;

    mtlsdo->width = width;
    mtlsdo->height = height;
    mtlsdo->isOpaque = isOpaque;

    if (mtlsdo->drawableType == MTLSD_WINDOW) {
        MTLContext_SetSurfaces(env, ptr_to_jlong(mtlsdo), ptr_to_jlong(mtlsdo));

        // we have to explicitly tell the NSOpenGLContext that its target
        // drawable has changed size
        MTLSDOps *cglsdo = (MTLSDOps *)mtlsdo->privOps;
        MTLContext *mtlc = cglsdo->configInfo->context;
        MTLCtxInfo *ctxinfo = (MTLCtxInfo *)mtlc->ctxInfo;

JNF_COCOA_ENTER(env);
        [ctxinfo->context update];
JNF_COCOA_EXIT(env);
    }
}
