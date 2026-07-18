plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.guitartiles.audiodecoder"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot engine AAR — compileOnly so it's not bundled in the plugin AAR
    compileOnly(fileTree(mapOf("dir" to "../android/build/libs/debug", "include" to listOf("*.aar"))))
}
