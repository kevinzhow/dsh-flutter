package com.example

import kotlin.math.max

/** Doc comment */
data class User(val id: Int, var name: String?, val tags: List<String> = emptyList())

sealed interface Result<out T> {
    data class Ok<T>(val value: T) : Result<T>
    object Fail : Result<Nothing>
}

abstract class Base(protected val size: Int) {
    abstract fun area(): Double
    open fun describe() = "size=$size"
}

fun <T : Comparable<T>> maxOf(a: T, b: T): T = if (a > b) a else b

suspend fun load(url: String): Result<String> {
    val text = "hello ${url.length} and $url \"quoted\"\n"
    val raw = """
        raw $text
    """.trimIndent()
    return when {
        url.isBlank() -> Result.Fail
        else -> Result.Ok(raw)
    }
}

fun main(args: Array<String>) {
    val xs = listOf(1, 2, 3).map { it * 2 }.filter { x -> x > 2 }
    val c = 'a'
    var n: Long = 0xFFL
    for (i in 0 until 10 step 2) n += i
    println(xs ?: emptyList<Int>())
    // comment
}
