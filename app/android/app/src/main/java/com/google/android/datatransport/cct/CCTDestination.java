package com.google.android.datatransport.cct;

import com.google.android.datatransport.Encoding;
import com.google.android.datatransport.runtime.EncodedDestination;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * T-159 (BR-SYNC-03): link-compatible stand-in for the Google datatransport CCT
 * destination. ML Kit's common library references this class by name for its
 * SDK-usage telemetry. The real artifact (transport-backend-cct) is excluded from
 * the build, because it is the uploader. With no backend registered under this
 * name, transport-runtime drops every event locally and nothing leaves the phone.
 * app-ci asserts the real backend never returns to the release classpath.
 */
public final class CCTDestination implements EncodedDestination {
    private static final Set<Encoding> SUPPORTED;

    static {
        Set<Encoding> s = new HashSet<>();
        s.add(Encoding.of("proto"));
        s.add(Encoding.of("json"));
        SUPPORTED = Collections.unmodifiableSet(s);
    }

    public static final CCTDestination INSTANCE = new CCTDestination("zaghlol-disabled", null);
    public static final CCTDestination LEGACY_INSTANCE = new CCTDestination("zaghlol-disabled", null);

    private final String name;
    private final byte[] extras;

    private CCTDestination(String name, byte[] extras) {
        this.name = name;
        this.extras = extras;
    }

    @Override
    public String getName() {
        return name;
    }

    @Override
    public byte[] getExtras() {
        return extras;
    }

    @Override
    public Set<Encoding> getSupportedEncodings() {
        return SUPPORTED;
    }
}
