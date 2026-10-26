package ru.koshelek.app.core

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import ru.koshelek.app.data.Account
import ru.koshelek.app.data.Tx
import ru.koshelek.app.data.TxKind
import java.io.File
import java.time.LocalDate

/** Выгрузка операций в CSV (тот же формат, что на iPhone — открывается в Excel). */
object Csv {
    private val header = listOf("Дата", "Тип", "Сумма", "Категория", "Счёт", "Куда", "Заметка")
    private fun q(v: String) = if (v.contains(';') || v.contains('"') || v.contains('\n')) "\"" + v.replace("\"", "\"\"") + "\"" else v

    fun share(ctx: Context, txs: List<Tx>, accounts: List<Account>) {
        fun name(id: String?) = accounts.firstOrNull { it.id == id }?.name ?: ""
        val rows = listOf(header) + txs.sortedBy { it.date }.map { t ->
            listOf(DF.iso(t.date), when (t.kind) { TxKind.INC -> "Доход"; TxKind.EXP -> "Расход"; TxKind.TR -> "Перевод" },
                Fmt.input(t.amount), if (t.kind == TxKind.TR) "" else Catalog.cat(t.cat).name, name(t.acc), name(t.to), t.note)
        }
        val f = File(ctx.cacheDir, "koshelek-${DF.iso(LocalDate.now())}.csv")
        f.writeText("﻿" + rows.joinToString("\r\n") { r -> r.joinToString(";") { q(it) } })
        val uri = FileProvider.getUriForFile(ctx, "ru.koshelek.app.files", f)
        ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/csv").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Выгрузка операций"))
    }
}
