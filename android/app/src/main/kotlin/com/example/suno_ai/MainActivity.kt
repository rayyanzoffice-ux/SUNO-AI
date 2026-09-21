package com.example.suno_ai

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = SunoEngine.get(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
