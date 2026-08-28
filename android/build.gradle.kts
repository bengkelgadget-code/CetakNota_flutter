allprojects {
    repositories {
        google()
        mavenCentral()
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
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            val androidExtension = project.extensions.findByName("android")
            if (androidExtension != null) {
                val namespaceProp = androidExtension.javaClass.methods.find { it.name == "getNamespace" }
                val namespaceValue = namespaceProp?.invoke(androidExtension)
                if (namespaceValue == null) {
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifestText = manifestFile.readText()
                        val matcher = java.util.regex.Pattern.compile("package=\"([^\"]+)\"").matcher(manifestText)
                        if (matcher.find()) {
                            val packageName = matcher.group(1)
                            val setNamespaceMethod = androidExtension.javaClass.methods.find { it.name == "setNamespace" }
                            setNamespaceMethod?.invoke(androidExtension, packageName)
                            println("Injected namespace $packageName into ${project.name}")
                        }
                    }
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
