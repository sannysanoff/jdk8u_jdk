package sun.java2d.macos;

import java.security.PrivilegedAction;

public class MacOSFlags {

    /**
     * Description of command-line flags.  All flags with [true|false]
     * values
     *      metalEnabled: usage: "-Djb.java2d.metal=[true|false]"
     */

    private static boolean metalEnabled;

    static {
        initJavaFlags();
        // initNativeFlags();
    }

    private static native boolean initNativeFlags();

    private static boolean getBooleanProp(String p, boolean defaultVal) {
        String propString = System.getProperty(p);
        boolean returnVal = defaultVal;
        if (propString != null) {
            if (propString.equals("true") ||
                propString.equals("t") ||
                propString.equals("True") ||
                propString.equals("T") ||
                propString.equals("")) // having the prop name alone
            {                          // is equivalent to true
                returnVal = true;
            } else if (propString.equals("false") ||
                       propString.equals("f") ||
                       propString.equals("False") ||
                       propString.equals("F"))
            {
                returnVal = false;
            }
        }
        return returnVal;
    }


    private static boolean getPropertySet(String p) {
        String propString = System.getProperty(p);
        return (propString != null) ? true : false;
    }

    private static void initJavaFlags() {
        java.security.AccessController.doPrivileged(
                (PrivilegedAction<Object>) () -> {
                    metalEnabled = getBooleanProp("jb.java2d.metal", false);
                    return null;
                });
    }

    public static boolean isMetalEnabled() {
        return metalEnabled;
    }
}
