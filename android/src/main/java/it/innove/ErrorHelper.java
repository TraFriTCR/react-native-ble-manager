package it.innove;

import android.util.Base64;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.WritableMap;

public final class ErrorHelper {

    public static WritableMap createATTResponseErrorWritableMap(int status) {
        WritableMap object = Arguments.createMap();
        object.putInt("type", BTErrorType.ATT_RESPONSE.getValue());
        object.putInt("status", status);
        return object;
    }
    public static WritableMap createInvalidStateErrorWritableMap(InvalidStateCode status) {
        WritableMap object = Arguments.createMap();
        object.putInt("type", BTErrorType.INVALID_STATE.getValue());
        object.putInt("status", status.getValue());
        return object;
    }
    public static WritableMap createtInvalidArgumentErrorWritableMap(String message) {
        WritableMap object = Arguments.createMap();
        object.putInt("type", BTErrorType.INVALID_ARGUMENT.getValue());
        object.putString("message", message);
        return object;
    }
    public static WritableMap createUnexpectedErrorWritableMap(String message) {
        WritableMap object = Arguments.createMap();
        object.putInt("type", BTErrorType.UNEXPECTED.getValue());
        object.putString("message", message);
        return object;
    }

    public enum BTErrorType {
        ATT_RESPONSE(1),
        INVALID_STATE(2),
        INVALID_ARGUMENT(3),
        UNEXPECTED(4);

        private final int value;

        BTErrorType(int value) {
            this.value = value;
        }

        public int getValue() {
            return value;
        }
    }

    public enum InvalidStateCode {
        UNKNOWN_BTERROR(1),
        NOT_SUPPORTED(2),
        CONNECTION_ATTEMPT_FAILED(3),
        PERIPHERAL_NOT_CONNECTED(4),
        PERIPHERAL_DISCONNECTED(5),
        PERIPHERAL_NOT_FOUND(6),
        RESOURCE_NOT_FOUND(7),
        BT_DISABLED(8),
        BT_UNSUPPORTED(9),
        GUI_RESOURCE_UNAVAILABLE(10),
        CONNECTION_LIMIT_REACHED(11);

        private final int value;

        InvalidStateCode(int value) {
            this.value = value;
        }

        public int getValue() {
            return value;
        }
    }
}
