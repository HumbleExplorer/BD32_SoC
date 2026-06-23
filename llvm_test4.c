/* Force 64-bit division - requires __udivdi3 from runtime */
unsigned long long a = 123456789012ULL;
unsigned long long b = 987654321ULL;
volatile unsigned long long result;

int main(void) {
    result = a / b;   /* force __udivdi3 */
    result = a * b;   /* force __muldi3 */
    return (int)result;
}
