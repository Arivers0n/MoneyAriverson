package ru.koshelek.app.ui

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import ru.koshelek.app.data.*
import java.io.ByteArrayOutputStream

/** Скан чеков и скриншотов банка: выбор источника → обработка с превью → проверка. */
@Composable
fun ScanFlow() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var chooser by remember { mutableStateOf(false) }
    var processing by remember { mutableStateOf<List<Bitmap>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    fun run(uris: List<Uri>) {
        if (uris.isEmpty()) return
        if (!Claude.available) { Router.say(if (Server.loggedIn) "ИИ на сервере не настроен" else "Скан чеков работает после входа"); return }
        scope.launch {
            val imgs = withContext(Dispatchers.IO) { uris.take(6).mapNotNull { loadScaled(ctx, it) } }
            if (imgs.isEmpty()) return@launch
            processing = imgs; error = null
            try {
                val bytes = withContext(Dispatchers.Default) { imgs.map { jpeg(it) } }
                val items = Brain.parseReceipts(bytes, Store.snapshot.value)
                if (items.isEmpty()) { Haptic.warning(); error = "Не нашёл операций на фото. Попробуйте снять чек ровнее."; return@launch }
                Haptic.success()
                processing = null
                Router.show(Route.Review(items, if (imgs.size == 1) "Со снимка" else "С ${imgs.size} снимков"))
            } catch (e: Exception) {
                Haptic.warning(); error = e.message ?: "Не получилось распознать"
            }
        }
    }

    val scanner = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            val res = GmsDocumentScanningResult.fromActivityResultIntent(r.data)
            run(res?.pages?.map { it.imageUri } ?: emptyList())
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(6)) { run(it) }

    fun openScanner() {
        val opts = GmsDocumentScannerOptions.Builder().setGalleryImportAllowed(true).setPageLimit(6)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG).setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL).build()
        val act = ctx as? Activity ?: return
        GmsDocumentScanning.getClient(opts).getStartScanIntent(act)
            .addOnSuccessListener { scanner.launch(IntentSenderRequest.Builder(it).build()) }
            .addOnFailureListener { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    }

    val req = Router.scanRequest
    LaunchedEffect(req) { if (req > 0) { Haptic.press(); chooser = true } }

    if (chooser) ScanSourceSheet({ chooser = false }, { chooser = false; openScanner() },
        { chooser = false; picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })

    AnimatedVisibility(processing != null, enter = fadeIn(tween(200)), exit = fadeOut(tween(250))) {
        var last by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
        processing?.let { last = it }
        ScanProcessing(last, error, onRetry = { processing = null; chooser = true }, onClose = { processing = null })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScanSourceSheet(onDismiss: () -> Unit, onCamera: () -> Unit, onGallery: () -> Unit) {
    val p = LocalPal.current
    ModalBottomSheet(onDismiss, containerColor = p.bg, dragHandle = { BottomSheetDefaults.DragHandle(color = p.tertiary) }) {
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Добавить из фото", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.text)
            Text("Чек из магазина или скриншот из банка — разберу суммы, даты и категории.", fontSize = 15.sp, color = p.secondary)
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SourceTile(Icons.Rounded.DocumentScanner, "Сканировать", "Камера сама найдёт края", p.accent, Modifier.weight(1f), onCamera)
                SourceTile(Icons.Rounded.PhotoLibrary, "Из галереи", "Скриншоты и фото", p.inc, Modifier.weight(1f), onGallery)
            }
        }
    }
}

@Composable
private fun SourceTile(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, sub: String, color: Color, modifier: Modifier, onClick: () -> Unit) {
    val p = LocalPal.current
    Column(modifier.cardBg(RoundedCornerShape(24.dp)).pressable(onClick, 0.96f).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(Brush.linearGradient(listOf(color.copy(alpha = 0.9f), color.copy(alpha = 0.6f)))), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(28.dp))
        }
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
        Text(sub, fontSize = 13.sp, color = p.secondary)
    }
}

/** Снимки веером, по ним бежит линия сканера. */
@Composable
private fun ScanProcessing(imgs: List<Bitmap>, error: String?, onRetry: () -> Unit, onClose: () -> Unit) {
    val p = LocalPal.current
    val inf = rememberInfiniteTransition(label = "scan")
    val line by inf.animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "line")
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.72f)).pressable({}, 1f), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(26.dp), modifier = Modifier.padding(30.dp)) {
            Box(Modifier.size(220.dp, 280.dp), contentAlignment = Alignment.Center) {
                imgs.take(3).forEachIndexed { i, b ->
                    val n = minOf(3, imgs.size); val rot = if (n == 1) 0f else (i - (n - 1) / 2f) * 7f
                    Image(b.asImageBitmap(), null, contentScale = ContentScale.Crop,
                        modifier = Modifier.size(190.dp, 250.dp).rotate(rot).clip(RoundedCornerShape(20.dp)).border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(20.dp)))
                }
                if (error == null) Box(Modifier.size(190.dp, 250.dp).clip(RoundedCornerShape(20.dp))) {
                    Box(Modifier.fillMaxWidth().height(70.dp).offset(y = (250 * line - 35).dp)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, p.accent.copy(alpha = 0.45f), Color.Transparent))))
                    Box(Modifier.fillMaxWidth().height(2.dp).offset(y = (250 * line).dp).background(p.accent))
                }
            }
            Text(error ?: "Читаю ${if (imgs.size == 1) "снимок" else "${imgs.size} снимка"}…", color = Color.White, fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            if (error != null) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Закрыть", color = Color.White, modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.15f)).pressable(onClose).padding(horizontal = 22.dp, vertical = 12.dp))
                Text("Другое фото", color = p.onAccent, fontWeight = FontWeight.SemiBold, modifier = Modifier.clip(RoundedCornerShape(50)).background(p.accent).pressable(onRetry).padding(horizontal = 22.dp, vertical = 12.dp))
            }
        }
    }
}

fun loadScaled(ctx: Context, uri: Uri, max: Int = 1600): Bitmap? = runCatching {
    val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o) }
    var s = 1
    while (o.outWidth / (s * 2) >= max || o.outHeight / (s * 2) >= max) s *= 2
    val b = ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = s }) } ?: return null
    val k = max.toFloat() / maxOf(b.width, b.height)
    if (k < 1f) Bitmap.createScaledBitmap(b, (b.width * k).toInt(), (b.height * k).toInt(), true) else b
}.getOrNull()

fun jpeg(b: Bitmap): ByteArray = ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
