allprojects {
    repositories {
        // 见 settings.gradle.kts：本机只能列出「可达」的仓库。
        // 不要加回 mavenCentral()（repo.maven.apache.org 不可达）——Gradle 遇到网络错误会直接
        // 判定解析失败而不跳到下一个仓库，会把 io.flutter:*_release 这类只能从 Flutter 仓库
        // 拿到的制品一起卡死。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        // Flutter 引擎制品所在仓库
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
