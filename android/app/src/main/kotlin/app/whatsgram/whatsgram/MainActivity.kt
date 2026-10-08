package app.whatsgram.whatsgram

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "whatsgram/storage").setMethodCallHandler { call, result ->
            if (call.method == "networkUnmetered") {
                val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                result.success(manager.activeNetwork != null && !manager.isActiveNetworkMetered)
                return@setMethodCallHandler
            }
            if (call.method == "chooseDirectory") {
                if (pending != null) { result.error("BUSY", "Finish the current selection first", null); return@setMethodCallHandler }
                pending = result
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }, 8022)
                return@setMethodCallHandler
            }
            if (call.method == "exportToDirectory") {
                val file = File(call.argument<String>("source") ?: "").canonicalFile
                val allowed = listOf(filesDir, cacheDir, File(applicationInfo.dataDir, "app_flutter"))
                if (!file.isFile || allowed.none { file.path.startsWith(it.canonicalPath + File.separator) }) {
                    result.error("INVALID_SOURCE", "Export source is not app-private", null); return@setMethodCallHandler
                }
                val tree = Uri.parse(call.argument<String>("directory"))
                val name = call.argument<String>("name") ?: "attachment"
                Thread {
                    var created: Uri? = null
                    try {
                        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                        var exists = false
                        contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
                            while (cursor.moveToNext()) {
                                if (cursor.getString(0) == name) {
                                    require(cursor.getLong(1) == file.length()) { "Existing filename has different contents" }
                                    val existingUri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(2))
                                    fun digest(input: java.io.InputStream): ByteArray {
                                        val sha = MessageDigest.getInstance("SHA-256")
                                        val buffer = ByteArray(65536)
                                        input.use { stream ->
                                            while (true) { val count = stream.read(buffer); if (count < 0) break; sha.update(buffer, 0, count) }
                                        }
                                        return sha.digest()
                                    }
                                    val originalHash = digest(file.inputStream())
                                    val existingHash = digest(requireNotNull(contentResolver.openInputStream(existingUri)))
                                    require(originalHash.contentEquals(existingHash)) { "Existing filename has different contents" }
                                    exists = true
                                    break
                                }
                            }
                        }
                        if (!exists) {
                            created = DocumentsContract.createDocument(contentResolver, parent, "application/octet-stream", name)
                            requireNotNull(created)
                            contentResolver.openOutputStream(created!!, "w").use { output ->
                                requireNotNull(output)
                                file.inputStream().use { it.copyTo(output) }
                            }
                        }
                        runOnUiThread { result.success(null) }
                    } catch (e: Exception) {
                        created?.let { runCatching { DocumentsContract.deleteDocument(contentResolver, it) } }
                        runOnUiThread { result.error("EXPORT_FAILED", "Cannot export to the selected directory; choose it again", null) }
                    }
                }.start()
                return@setMethodCallHandler
            }
            if (call.method != "saveFile") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("BUSY", "Finish the current export first", null); return@setMethodCallHandler }
            val file = File(call.argument<String>("source") ?: "").canonicalFile
            val allowed = listOf(filesDir, cacheDir, File(applicationInfo.dataDir, "app_flutter"))
            if (!file.isFile || allowed.none { file.path.startsWith(it.canonicalPath + File.separator) }) {
                result.error("INVALID_SOURCE", "Export source is not an app-private file", null)
                return@setMethodCallHandler
            }
            source = file
            pending = result
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "attachment")
            }
            startActivityForResult(intent, 8021)
        }
    }
    @Deprecated("Legacy activity callback used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 8022) {
            val result = pending ?: return
            pending = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
            try {
                contentResolver.takePersistableUriPermission(uri, data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
                result.success(uri.toString())
            } catch (e: Exception) { result.error("DIRECTORY_PERMISSION", "Could not retain directory access", null) }
            return
        }
        if (requestCode != 8021) return
        val result = pending ?: return
        val file = source
        pending = null
        source = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) { result.success(null); return }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w").use { output ->
                    requireNotNull(output) { "Destination is unavailable" }
                    file.inputStream().use { it.copyTo(output) }
                }
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runCatching { android.provider.DocumentsContract.deleteDocument(contentResolver, uri) }
                runOnUiThread { result.error("EXPORT_FAILED", "Unable to write the selected document", null) }
            }
        }.start()
    }
}
