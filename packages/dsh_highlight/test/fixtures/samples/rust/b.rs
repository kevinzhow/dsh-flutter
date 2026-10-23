#![allow(dead_code)]
use std::{io::{self, Read}, sync::Arc};
mod inner { pub(crate) fn f() {} }
macro_rules! square { ($x:expr) => { $x * $x }; }

#[derive(Debug)]
#[repr(u8)]
enum Op { Add = 1, Sub = 2 }

trait Shape: Send + Sync { const SIDES: usize; type Out; fn area(&self) -> Self::Out where Self: Sized; }

impl<'a, T: 'a + Clone> Iterator for Wrapper<'a, T> where T: Default {
    type Item = &'a T;
    fn next(&mut self) -> Option<Self::Item> { None }
}

pub async fn run<F, Fut>(f: F) -> Result<(), Box<dyn std::error::Error>>
where F: FnOnce() -> Fut, Fut: std::future::Future<Output = ()> {
    let v: Vec<_> = (0..10).filter(|n| n % 2 == 0).map(|n| n as f32 * 1.5e2).collect();
    let s = "esc \" \\ \n \x41 \u{1F600}";
    let bytes = b"bytes\xff";
    let raw = r##"has "# inside"##;
    let ch = '\'';
    let lt: &'static str = "x";
    let t = 1_000i64 + 0xFFu8 as i64 + 0b11 + 0o7;
    loop { break 'outer; }
    let Some(x) = opt else { return Ok(()) };
    println!("{x:?} {0} {name}", 1, name = "n");
    let r = &mut *Box::new(5);
    let _ = x?.y.await?;
    Ok(())
}
