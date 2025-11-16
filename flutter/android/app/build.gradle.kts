import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else {
    logger.warn("key.properties not found - release builds will fail until it is provided.")
}

android {
    namespace = "com.steinmetzbnaya.quickclickmatch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                val storeFilePath = keystoreProperties["storeFile"] as String?
                val storePassword = keystoreProperties["storePassword"] as String?
                val keyAlias = keystoreProperties["keyAlias"] as String?
                val keyPassword = keystoreProperties["keyPassword"] as String?

                require(!storeFilePath.isNullOrBlank()) { "storeFile missing from key.properties" }
                require(!storePassword.isNullOrBlank()) { "storePassword missing from key.properties" }
                require(!keyAlias.isNullOrBlank()) { "keyAlias missing from key.properties" }
                require(!keyPassword.isNullOrBlank()) { "keyPassword missing from key.properties" }

                storeFile = file(storeFilePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    val flutterVersionCode = project.findProperty("flutter.versionCode")?.toString()?.toIntOrNull()
    val flutterVersionName = project.findProperty("flutter.versionName")?.toString()

    defaultConfig {
        applicationId = "com.steinmetzbnaya.quickclickmatch"
        minSdk = 24
        targetSdk = 33
        versionCode = flutterVersionCode ?: 2
        versionName = flutterVersionName ?: "1.0.1"

        // --- CRITICAL: MultiDex is ENABLED in the default config ---
        multiDexEnabled = true
    }

    buildTypes {
        // --- DEBUG BUILD CONFIGURATION (For flutter run) ---
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }

        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Release keystore not configured. Falling back to debug signing.")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro"),
            )
        }
    }
    val requireReleaseKeystore = System.getenv("REQUIRE_RELEASE_KEYSTORE")?.equals("true", ignoreCase = true) == true

    gradle.taskGraph.whenReady {
        val runningReleaseTask = allTasks.any { task ->
            task.name.contains("Release") &&
                (task.name.contains("bundle", ignoreCase = true) ||
                    task.name.contains("assemble", ignoreCase = true))
        }
        if (runningReleaseTask && !keystorePropertiesFile.exists()) {
            val message = "Missing key.properties. Provide release signing credentials before building release artifacts."
            if (requireReleaseKeystore) {
                throw GradleException(message)
            } else {
                logger.warn("$message Falling back to debug signing for local builds.")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // --- CRITICAL FIX: MultiDex DEPENDENCY IS EXPLICITLY ADDED HERE ---
    implementation("androidx.multidex:multidex:2.0.1")
}
