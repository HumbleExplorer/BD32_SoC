unsigned long long result;
unsigned long long a = 123456789012ULL;
unsigned long long b = 987654321ULL;

int main(void) {
    result = a / b;   /* requires __udivdi3 */
    result = a * b;   /* requires __muldi3 */
    return (int)result;
}
