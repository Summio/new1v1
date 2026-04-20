plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.toivan.mtcamera.mt_plugin"
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

dependencies {
    compileOnly(files("${rootProject.projectDir}/app/libs/FaceBeauty.aar"))
}
