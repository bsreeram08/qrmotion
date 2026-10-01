plugins {
    id("com.android.library")
    kotlin("plugin.compose")
}

base.archivesName = "qrmotion-compose"

android {
    namespace = "io.github.bsreeram08.qrmotion.compose"
    compileSdk = 37
    defaultConfig {
        minSdk = 23
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

kotlin {
    explicitApi()
}

dependencies {
    api(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.ui:ui")
}
