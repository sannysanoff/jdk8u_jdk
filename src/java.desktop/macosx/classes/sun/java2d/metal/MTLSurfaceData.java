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

package sun.java2d.metal;

import sun.java2d.SunGraphics2D;
import sun.java2d.SurfaceData;
import sun.java2d.opengl.OGLSurfaceData;
import sun.lwawt.macosx.CPlatformView;

import java.awt.*;
import java.awt.image.ColorModel;

public abstract class MTLSurfaceData extends MTLSurfaceDataBase {

    protected final int scale;
    protected final int width;
    protected final int height;
    protected CPlatformView pView;
    private MTLGraphicsConfig graphicsConfig;

    native void validate(int xoff, int yoff, int width, int height, boolean isOpaque);

    private native void initOps(long pConfigInfo, long pPeerData, long layerPtr,
                                int xoff, int yoff, boolean isOpaque);

    protected MTLSurfaceData(MTLGraphicsConfig gc, ColorModel cm, int type,
                             int width, int height) {
        super(gc, cm, type);
        // TEXTURE shouldn't be scaled, it is used for managed BufferedImages.
        scale = type == TEXTURE ? 1 : gc.getDevice().getScaleFactor();
        this.width = width * scale;
        this.height = height * scale;
    }

    protected MTLSurfaceData(CPlatformView pView, MTLGraphicsConfig gc,
                             ColorModel cm, int type, int width, int height)
    {
        this(gc, cm, type, width, height);
        this.pView = pView;
        this.graphicsConfig = gc;

        long pConfigInfo = gc.getNativeConfigInfo();
        long pPeerData = 0L;
        boolean isOpaque = true;
        if (pView != null) {
            pPeerData = pView.getAWTView();
            isOpaque = pView.isOpaque();
        }
        MTLGraphicsConfig.refPConfigInfo(pConfigInfo);
        initOps(pConfigInfo, pPeerData, 0, 0, 0, isOpaque);
    }

    protected MTLSurfaceData(MTLLayer layer, MTLGraphicsConfig gc,
                             ColorModel cm, int type, int width, int height)
    {
        this(gc, cm, type, width, height);
        this.graphicsConfig = gc;

        long pConfigInfo = gc.getNativeConfigInfo();
        long layerPtr = 0L;
        boolean isOpaque = true;
        if (layer != null) {
            layerPtr = layer.getPointer();
            isOpaque = layer.isOpaque();
        }
        MTLGraphicsConfig.refPConfigInfo(pConfigInfo);
        initOps(pConfigInfo, 0, layerPtr, 0, 0, isOpaque);
    }

    @Override //SurfaceData
    public GraphicsConfiguration getDeviceConfiguration() {
        return graphicsConfig;
    }

    /**
     * Creates a SurfaceData object representing the primary (front) buffer of
     * an on-screen Window.
     */
    public static MTLWindowSurfaceData createData(CPlatformView pView) {
        MTLGraphicsConfig gc = getGC(pView);
        return new MTLWindowSurfaceData(pView, gc);
    }

    /**
     * Creates a SurfaceData object representing the intermediate buffer
     * between the Java2D flusher thread and the AppKit thread.
     */
    public static MTLLayerSurfaceData createData(MTLLayer layer) {
        MTLGraphicsConfig gc = getGC(layer);
        Rectangle r = layer.getBounds();
        return new MTLLayerSurfaceData(layer, gc, r.width, r.height);
    }

    /**
     * Creates a SurfaceData object representing the back buffer of a
     * double-buffered on-screen Window.
     */
    public static MTLOffScreenSurfaceData createData(CPlatformView pView,
                                                     Image image, int type) {
        MTLGraphicsConfig gc = getGC(pView);
        Rectangle r = pView.getBounds();
        if (type == FLIP_BACKBUFFER) {
            return new MTLOffScreenSurfaceData(pView, gc, r.width, r.height,
                    image, gc.getColorModel(), FLIP_BACKBUFFER);
        } else {
            return new CGLVSyncOffScreenSurfaceData(pView, gc, r.width,
                    r.height, image, gc.getColorModel(), type);
        }
    }

    /**
     * Creates a SurfaceData object representing an off-screen buffer (either a
     * FBO or Texture).
     */
    public static MTLOffScreenSurfaceData createData(MTLGraphicsConfig gc,
                                                     int width, int height, ColorModel cm, Image image, int type) {
        return new MTLOffScreenSurfaceData(null, gc, width, height, image, cm,
                type);
    }

    public static MTLGraphicsConfig getGC(CPlatformView pView) {
        if (pView != null) {
            return (MTLGraphicsConfig)pView.getGraphicsConfiguration();
        } else {
            // REMIND: this should rarely (never?) happen, but what if
            // default config is not CGL?
            GraphicsEnvironment env = GraphicsEnvironment
                .getLocalGraphicsEnvironment();
            GraphicsDevice gd = env.getDefaultScreenDevice();
            return (MTLGraphicsConfig) gd.getDefaultConfiguration();
        }
    }

    public static MTLGraphicsConfig getGC(MTLLayer layer) {
        return (MTLGraphicsConfig)layer.getGraphicsConfiguration();
    }

    public void validate() {
        // Overridden in MTLWindowSurfaceData below
    }

    @Override
    public double getDefaultScaleX() {
        return scale;
    }

    @Override
    public double getDefaultScaleY() {
        return scale;
    }

    protected native void clearWindow();

    public static class MTLWindowSurfaceData extends MTLSurfaceData {

        public MTLWindowSurfaceData(CPlatformView pView,
                                    MTLGraphicsConfig gc) {
            super(pView, gc, gc.getColorModel(), WINDOW, 0, 0);
        }

        @Override
        public SurfaceData getReplacement() {
            return pView.getSurfaceData();
        }

        @Override
        public Rectangle getBounds() {
            Rectangle r = pView.getBounds();
            return new Rectangle(0, 0, r.width, r.height);
        }

        /**
         * Returns destination Component associated with this SurfaceData.
         */
        @Override
        public Object getDestination() {
            return pView.getDestination();
        }

        public void validate() {
            MTLRenderQueue rq = MTLRenderQueue.getInstance();
            rq.lock();
            try {
                rq.flushAndInvokeNow(() -> {
                    Rectangle peerBounds = pView.getBounds();
                    validate(0, 0, peerBounds.width, peerBounds.height, pView.isOpaque());
                });
            } finally {
                rq.unlock();
            }
        }

        @Override
        public void invalidate() {
            super.invalidate();
            clearWindow();
        }
    }

    /**
     * A surface which implements an intermediate buffer between
     * the Java2D flusher thread and the AppKit thread.
     *
     * This surface serves as a buffer attached to a MTLLayer and
     * the layer redirects all painting to the buffer's graphics.
     */
    public static class MTLLayerSurfaceData extends MTLSurfaceData {

        private MTLLayer layer;

        public MTLLayerSurfaceData(MTLLayer layer, MTLGraphicsConfig gc,
                                   int width, int height) {
            super(layer, gc, gc.getColorModel(), FBOBJECT, width, height);
            this.layer = layer;
            initSurface(this.width, this.height);
        }

        @Override
        public SurfaceData getReplacement() {
            return layer.getSurfaceData();
        }

        @Override
        public boolean isOnScreen() {
            return true;
        }

        @Override
        public Rectangle getBounds() {
            return new Rectangle(width, height);
        }

        @Override
        public Object getDestination() {
            return layer.getDestination();
        }

        @Override
        public int getTransparency() {
            return layer.getTransparency();
        }

        @Override
        public void invalidate() {
            super.invalidate();
            clearWindow();
        }
    }

    /**
     * A surface which implements a v-synced flip back-buffer with COPIED
     * FlipContents.
     *
     * This surface serves as a back-buffer to the outside world, while it is
     * actually an offscreen surface. When the BufferStrategy this surface
     * belongs to is showed, it is first copied to the real private
     * FLIP_BACKBUFFER, which is then flipped.
     */
    public static class CGLVSyncOffScreenSurfaceData extends
            MTLOffScreenSurfaceData {
        private MTLOffScreenSurfaceData flipSurface;

        public CGLVSyncOffScreenSurfaceData(CPlatformView pView,
                                            MTLGraphicsConfig gc, int width, int height, Image image,
                                            ColorModel cm, int type) {
            super(pView, gc, width, height, image, cm, type);
            flipSurface = MTLSurfaceData.createData(pView, image,
                    FLIP_BACKBUFFER);
        }

        public SurfaceData getFlipSurface() {
            return flipSurface;
        }

        @Override
        public void flush() {
            flipSurface.flush();
            super.flush();
        }
    }

    public static class MTLOffScreenSurfaceData extends MTLSurfaceData {
        private Image offscreenImage;

        public MTLOffScreenSurfaceData(CPlatformView pView,
                                       MTLGraphicsConfig gc, int width, int height, Image image,
                                       ColorModel cm, int type) {
            super(pView, gc, cm, type, width, height);
            offscreenImage = image;
            initSurface(this.width, this.height);
        }

        @Override
        public SurfaceData getReplacement() {
            return restoreContents(offscreenImage);
        }

        @Override
        public Rectangle getBounds() {
            if (type == FLIP_BACKBUFFER) {
                Rectangle r = pView.getBounds();
                return new Rectangle(0, 0, r.width, r.height);
            } else {
                return new Rectangle(width, height);
            }
        }

        /**
         * Returns destination Image associated with this SurfaceData.
         */
        @Override
        public Object getDestination() {
            return offscreenImage;
        }
    }

    // Mac OS X specific APIs for JOGL/Java2D bridge...

    // given a surface create and attach GL context, then return it
    private static native long createCGLContextOnSurface(MTLSurfaceData sd,
                                                         long sharedContext);

    public static long createOGLContextOnSurface(Graphics g, long sharedContext) {
        SurfaceData sd = ((SunGraphics2D) g).surfaceData;
        if ((sd instanceof MTLSurfaceData) == true) {
            MTLSurfaceData cglsd = (MTLSurfaceData) sd;
            return createCGLContextOnSurface(cglsd, sharedContext);
        } else {
            return 0L;
        }
    }

    // returns whether or not the makeCurrent operation succeeded
    static native boolean makeCGLContextCurrentOnSurface(MTLSurfaceData sd,
                                                         long ctx);

    public static boolean makeOGLContextCurrentOnSurface(Graphics g, long ctx) {
        SurfaceData sd = ((SunGraphics2D) g).surfaceData;
        if ((ctx != 0L) && ((sd instanceof MTLSurfaceData) == true)) {
            MTLSurfaceData cglsd = (MTLSurfaceData) sd;
            return makeCGLContextCurrentOnSurface(cglsd, ctx);
        } else {
            return false;
        }
    }

    // additional cleanup
    private static native void destroyCGLContext(long ctx);

    public static void destroyOGLContext(long ctx) {
        if (ctx != 0L) {
            destroyCGLContext(ctx);
        }
    }

    public static void dispose(long pData, long pConfigInfo) {
        OGLSurfaceData.dispose(pData, pConfigInfo);
        MTLGraphicsConfig.deRefPConfigInfo(pConfigInfo);
    }
}
