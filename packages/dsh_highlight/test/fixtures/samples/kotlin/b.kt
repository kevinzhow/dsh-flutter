@file:JvmName("Util")
package com.example.util

import java.io.*
import kotlinx.coroutines.flow.Flow as F

@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
annotation class Marker(val value: String = "")

interface Repo<T : Any> {
    suspend fun find(id: Long): T?
    val size: Int get() = 0
}

class Impl<T : Any> private constructor(private val items: MutableMap<Long, T> = mutableMapOf()) : Repo<T>, AutoCloseable {
    companion object { const val MAX = 1_000; fun <T : Any> create() = Impl<T>() }
    override suspend fun find(id: Long) = items[id]
    override fun close() {}
    inner class Cursor { operator fun invoke(): Int = 0 }
    infix fun Int.plus2(o: Int) = this + o
}

object Singleton { lateinit var name: String }
enum class Mode(val v: Int) { A(1) { override fun f() = 1 }, B(2); open fun f() = v }

inline fun <reified T> typeName() = T::class.simpleName ?: "?"
tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)

fun main() {
    val s = "tab\t \"q\" \$notTemplate ${1 + 2} $x é"
    val ch = '\n'; val l = 123L; val f = 1.5f; val h = 0xFF; val b = 0b101
    val lambda: (Int) -> Int = { it * 2 }
    val r = 1..10; val nullable: String? = null
    println(nullable?.length ?: -1)
    when (val v = lambda(2)) { in 1..3 -> {}; is Int -> {}; else -> {} }
    loop@ for (i in 1..3) { if (i == 2) continue@loop }
    val raw = """
        |raw ${s}
    """.trimMargin()
    val x by lazy { 1 }
    try { error("x") } catch (e: Exception) { throw e } finally { }
}
