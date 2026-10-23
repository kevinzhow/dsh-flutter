#include <iostream>
#include <vector>
#include <memory>

namespace demo {

template <typename T, size_t N = 4>
class Buffer final : public Base {
public:
    explicit Buffer(std::string name) : name_(std::move(name)) {}
    virtual ~Buffer() = default;
    constexpr size_t size() const noexcept { return N; }
    auto get(size_t i) const -> const T& { return data_.at(i); }

private:
    std::vector<T> data_;
    std::string name_;
};

struct Point { int x = 0, y = 0; };

enum class Color : unsigned char { Red, Green };

} // namespace demo

int main() {
    auto p = std::make_unique<demo::Buffer<int>>("buf");
    auto lambda = [&](int a, auto b) mutable { return a + b; };
    std::string raw = R"(raw "text" \n)";
    std::cout << "value: " << lambda(1, 2) << '\n';
    try {
        throw std::runtime_error("oops");
    } catch (const std::exception &e) {
        std::cerr << e.what() << std::endl;
    }
    static_assert(sizeof(int) >= 4, "int too small");
    return 0;
}
