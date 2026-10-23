#include <algorithm>
#include <string_view>
using namespace std::literals;

template <typename T> concept Numeric = std::is_arithmetic_v<T>;
template <Numeric T> auto sum(std::span<const T> xs) requires (sizeof(T) > 1) { return std::accumulate(xs.begin(), xs.end(), T{}); }

class [[nodiscard]] Widget : public std::enable_shared_from_this<Widget> {
    int value_{};
    mutable std::mutex mu_;
public:
    Widget() noexcept = default;
    Widget(const Widget&) = delete;
    Widget& operator=(Widget&&) noexcept;
    friend std::ostream& operator<<(std::ostream& os, const Widget& w);
    virtual int compute(int x) const override final { return x <=> 0; }
    static constexpr double kPi = 3.14159265358979L;
    template <class U> void set(U&& u) { value_ = std::forward<U>(u); }
};

int main(int argc, char* argv[]) {
    auto lam = [=, &argc]<typename T>(T t) -> decltype(auto) { return t + argc; };
    std::map<std::string, std::vector<int>> m{{"a", {1, 2}}, {"b", {}}};
    for (auto& [k, v] : m) { std::cout << k << ": " << v.size() << "\n"; }
    const char* s = u8"unicode é" "concat";
    auto str = "view"sv; auto n = 100'000ull; auto h = 0x1.8p3;
    std::unique_ptr<int[]> arr(new int[10]);
    if constexpr (sizeof(int) == 4) { co_await foo(); }
    switch (argc) { case 1: [[fallthrough]]; default: break; }
    #pragma omp parallel for
    for (int i = 0; i < 10; ++i) {}
    return static_cast<int>(reinterpret_cast<uintptr_t>(&argc) & 0xF);
}
