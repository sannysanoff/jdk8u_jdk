package quality.metal;

import org.junit.Test;
import quality.util.RenderUtil;

import javax.swing.*;
import java.awt.*;
import java.awt.image.BufferedImage;

public class MetalRenderTest {

    @Test
    public void testMetal() throws Exception {
        BufferedImage bi = RenderUtil.capture(120, 120,
                graphics2D -> {
                    graphics2D.fillRect(0, 0, 50, 50);
                    graphics2D.fillRect(30, 30, 150, 150);

                });
    }
    @Test
    public void testMetal1() throws Exception {
        JFrame[] f = new JFrame[1];
        SwingUtilities.invokeAndWait(() -> {
            f[0] = new JFrame();

            f[0].setSize(300, 300);
            // for frame border effects,
            // e.g. rounded frame
            f[0].setVisible(true);
        });

        Thread.sleep(4000);
    }

    @Test
    public void testMetal2() throws Exception {
        Frame[] f = new Frame[1];
        SwingUtilities.invokeAndWait(() -> {
            f[0] = new Frame();

            f[0].setSize(300, 300);
            // for frame border effects,
            // e.g. rounded frame
            f[0].setVisible(true);
        });

        Thread.sleep(4000);
    }
}
