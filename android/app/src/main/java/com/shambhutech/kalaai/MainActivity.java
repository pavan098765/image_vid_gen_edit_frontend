package com.shambhutech.kalaai;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;

import androidx.annotation.NonNull;

import com.ryanheise.audioservice.AudioServiceActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends AudioServiceActivity {
    private static final String CHANNEL = "kala_ai/audio_library";
    private static final String ALBUM = "Kala_AI";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!"saveAudio".equals(call.method)) {
                        result.notImplemented();
                        return;
                    }
                    String name = call.argument("name");
                    String mime = call.argument("mime");
                    byte[] bytes = call.argument("bytes");
                    if (name == null || name.isEmpty() || bytes == null) {
                        result.error("bad_args", "Audio name and bytes are required", null);
                        return;
                    }
                    if (mime == null || mime.isEmpty()) {
                        mime = "audio/mpeg";
                    }
                    try {
                        String path = saveAudio(name, mime, bytes);
                        result.success(path);
                    } catch (Exception error) {
                        result.error("save_failed", error.getMessage(), null);
                    }
                });
    }

    private String saveAudio(String name, String mime, byte[] bytes) throws Exception {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveWithMediaStore(name, mime, bytes);
        }
        return saveLegacy(name, bytes);
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private String saveWithMediaStore(String name, String mime, byte[] bytes) throws Exception {
        ContentResolver resolver = getContentResolver();
        String relative = Environment.DIRECTORY_MUSIC + "/" + ALBUM + "/";
        try {
            resolver.delete(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    MediaStore.Audio.Media.DISPLAY_NAME + "=? AND " +
                            MediaStore.Audio.Media.RELATIVE_PATH + "=?",
                    new String[]{name, relative}
            );
        } catch (Exception ignored) {
            // A previous copy can stay. The new file still gets a unique store row.
        }

        ContentValues values = new ContentValues();
        values.put(MediaStore.Audio.Media.DISPLAY_NAME, name);
        values.put(MediaStore.Audio.Media.MIME_TYPE, mime);
        values.put(MediaStore.Audio.Media.RELATIVE_PATH, relative);
        values.put(MediaStore.Audio.Media.IS_PENDING, 1);
        Uri uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values);
        if (uri == null) {
            throw new IllegalStateException("MediaStore did not accept the audio file");
        }
        try (OutputStream out = resolver.openOutputStream(uri)) {
            if (out == null) {
                throw new IllegalStateException("Could not open the audio file");
            }
            out.write(bytes);
        }
        values.clear();
        values.put(MediaStore.Audio.Media.IS_PENDING, 0);
        resolver.update(uri, values, null, null);

        String stored = queryDataPath(resolver, uri);
        if (stored != null && new File(stored).exists()) {
            return stored;
        }
        File probe = new File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                ALBUM + "/" + name
        );
        if (probe.exists()) {
            return probe.getAbsolutePath();
        }
        return null;
    }

    private String queryDataPath(ContentResolver resolver, Uri uri) {
        try (Cursor cursor = resolver.query(
                uri,
                new String[]{MediaStore.Audio.Media.DATA},
                null,
                null,
                null
        )) {
            if (cursor != null && cursor.moveToFirst()) {
                return cursor.getString(0);
            }
        } catch (Exception ignored) {
            return null;
        }
        return null;
    }

    private String saveLegacy(String name, byte[] bytes) throws Exception {
        File dir = new File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                ALBUM
        );
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("Could not create Music/Kala_AI");
        }
        File outFile = new File(dir, name);
        try (FileOutputStream out = new FileOutputStream(outFile, false)) {
            out.write(bytes);
        }
        return outFile.getAbsolutePath();
    }
}
