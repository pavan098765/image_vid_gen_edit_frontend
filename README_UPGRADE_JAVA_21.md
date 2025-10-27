Upgrade to Java 21 (LTS) — Manual steps

This project targets Java 21 for Android builds and Gradle compatibility. The environment where automated upgrade tools are unavailable requires manual setup.

Steps to upgrade your local dev environment to Java 21:

1. Install a JDK 21 distribution (Adoptium/Eclipse Temurin, Azul Zulu, Oracle JDK, etc.).
   - Windows: download and run the installer and note the install path (for example: C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.x)

2. Set JAVA_HOME and update PATH (PowerShell example):

```powershell
# Run in an elevated PowerShell or your normal shell session
[System.Environment]::SetEnvironmentVariable('JAVA_HOME','C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.x','User')
$env:JAVA_HOME = 'C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.x'
$env:Path = $env:JAVA_HOME + '\\bin;' + $env:Path
```

3. Verify Java is 21:

```powershell
java -version
```

4. (Optional) Configure Gradle to use a specific JDK installation by editing or creating `gradle.properties` at the project root (this repo includes an example `gradle.properties` named `gradle.properties.example`).

- Example entry to add to `gradle.properties`:

```
# Replace the path with your JDK 21 installation path
org.gradle.java.home=C:/Program Files/Eclipse Adoptium/jdk-21.0.x
```

5. Verify Gradle and Android builds using JDK 21:

```powershell
cd android
./gradlew -v
./gradlew assembleDebug
```

Notes
- The project's `android/app/build.gradle` already sets Java compatibility to 21 (sourceCompatibility/targetCompatibility and Kotlin jvmTarget = "21").
- If your environment uses Android Studio, set the JDK location in the IDE's settings to your JDK 21 installation.

If you want, I can add a `gradle.properties` file with a commented placeholder for `org.gradle.java.home`, or modify CI pipeline files to use JDK 21. Tell me which you'd prefer.