plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.example.escaner"
    compileSdkVersion 36

    defaultConfig {
        applicationId "com.example.escaner"
        minSdkVersion 21
        targetSdkVersion 36
        versionCode 2
        versionName "1.1.0"
    }

    // Java 17
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    // Kotlin JVM 17
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig signingConfigs.debug
            minifyEnabled false
            shrinkResources false
        }
    }
}

flutter {
    source "../.."
}
