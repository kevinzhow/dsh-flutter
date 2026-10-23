use std::collections::HashMap;
use std::fmt::{self, Display};

#[derive(Debug, Clone, PartialEq)]
pub struct Point<T> {
    pub x: T,
    y: T,
}

pub trait Area {
    fn area(&self) -> f64;
}

impl<T: Display> fmt::Display for Point<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({}, {})", self.x, self.y)
    }
}

enum Shape { Circle(f64), Rect { w: f64, h: f64 }, Unit }

/// Doc comment
fn classify(n: i32) -> &'static str {
    match n {
        0 => "zero",
        x if x < 0 => "neg",
        1..=9 => "small",
        _ => "big",
    }
}

fn main() {
    let mut map: HashMap<String, Vec<u8>> = HashMap::new();
    map.entry("k".to_string()).or_default().push(b'a');
    let raw = r#"raw "quoted" \n"#;
    let c = 'x';
    let t = (1u32, 2.5f64, "tab\t\u{1F600}");
    let closure = |a: i32, b| -> i32 { a + b };
    /* block /* nested */ comment */
    if let Some(v) = map.get("k") {
        println!("{:?} {raw} {}", v, closure(1, 2));
    }
    unsafe { let p = &t as *const _; }
}
