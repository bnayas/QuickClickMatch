int mod(int a, int q) => ((a % q) + q) % q;

int modInv(int a, int q) {
  for (int i = 1; i < q; i++) {
    if ((a * i) % q == 1) return i;
  }
  throw Exception("No modular inverse for $a mod $q");
} 