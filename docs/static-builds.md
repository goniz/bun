# Static Musl Builds

## Overview

Bun provides fully static musl builds for maximum portability across Linux distributions. These binaries have **zero dynamic library dependencies** and can run on any Linux system with a compatible kernel (2.6.32+).

### Key Benefits

- ✅ **Universal compatibility**: Run on any Linux distribution (Alpine, Ubuntu, Debian, RHEL, Amazon Linux, etc.)
- ✅ **No dependencies**: No need for musl or glibc to be installed
- ✅ **Container-friendly**: Works in minimal containers (scratch, distroless, BusyBox)
- ✅ **Predictable behavior**: No dynamic library version conflicts
- ❌ **Slightly larger**: ~5-10MB larger than dynamic builds (~105-110MB vs ~100MB)

## Differences from Dynamic Builds

| Feature         | Dynamic Musl       | Static Musl                                     |
| --------------- | ------------------ | ----------------------------------------------- |
| Binary size     | ~100MB             | ~105-110MB                                      |
| Portability     | Requires musl libc | Runs anywhere                                   |
| Startup time    | ~10ms              | ~12ms                                           |
| FFI/dlopen      | Fully supported    | Limited (see [Limitations](#known-limitations)) |
| CA certificates | Auto-detected      | External file required                          |

## Building from Source

### Prerequisites

**Alpine Linux 3.22+** (recommended):

```bash
apk add build-base bash cmake ninja git libstdc++-dev
```

The static libraries (`libstdc++.a`, `libatomic.a`) are included in the `g++` package on Alpine.

**Other distros**: Use an Alpine Docker container (recommended)

### Build Command

```bash
cmake -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DABI=musl \
  -DSTATIC_MUSL=ON \
  .

ninja
```

### Using Docker

```bash
docker run --rm -it -v $(pwd):/workspace -w /workspace alpine:3.22 sh

# Inside container:
apk add build-base bash cmake ninja git libstdc++-dev
cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DABI=musl -DSTATIC_MUSL=ON .
ninja
```

### Verification

After building, verify the binary is truly static:

```bash
./scripts/verify-static-musl.sh build/bun
```

This script checks:

- File type is "statically linked"
- `ldd` reports "not a dynamic executable"
- `readelf -d` shows no NEEDED entries
- `readelf -l` shows no interpreter
- Binary executes successfully

## Known Limitations

### 1. CA Certificates

Static builds **do not bundle CA certificates** for HTTPS/TLS connections. You must provide them externally.

**Solution**: Set environment variable pointing to CA certificate file or directory:

```bash
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# Or
export SSL_CERT_DIR=/etc/ssl/certs
```

**Common certificate locations by distribution**:

- Alpine/Debian/Ubuntu: `/etc/ssl/certs/ca-certificates.crt`
- RHEL/Fedora/Amazon Linux: `/etc/pki/tls/certs/ca-bundle.crt`
- OpenSUSE: `/etc/ssl/ca-bundle.pem`

**For containers**, install CA certificates package:

```dockerfile
# Alpine
RUN apk add ca-certificates

# Debian/Ubuntu
RUN apt-get update && apt-get install -y ca-certificates
```

### 2. FFI / Dynamic Module Loading

The `bun:ffi` module's `dlopen()` function has limitations in fully static builds:

```javascript
import { dlopen } from "bun:ffi";
// May not work or may have limited functionality
```

**Workaround**:

- Use dynamic musl builds if you need FFI
- Or compile native code statically and link at build time

### 3. DNS Resolution Differences

Musl uses a simpler DNS resolver than glibc:

- No `/etc/nsswitch.conf` support
- Direct `/etc/resolv.conf` parsing
- May behave differently in complex network setups (VPNs, split DNS, custom NSS modules)

This affects both static and dynamic musl builds.

### 4. Locale Support

Musl provides basic locale support. Applications expecting full glibc locale data may need adjustments.

## Deployment Examples

### Minimal Docker Container (Scratch)

```dockerfile
FROM scratch
COPY bun-linux-x64-musl-static /bun
COPY ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/bun"]
CMD ["--help"]
```

**Image size**: ~105MB (just the binary + certificates)

### Distroless

```dockerfile
FROM gcr.io/distroless/static-debian12
COPY bun-linux-x64-musl-static /usr/local/bin/bun
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/usr/local/bin/bun"]
```

### Alpine

```dockerfile
FROM alpine:3.22
# No additional packages needed!
COPY bun-linux-x64-musl-static /usr/local/bin/bun
CMD ["bun", "--version"]
```

### AWS Lambda

```dockerfile
FROM public.ecr.aws/lambda/provided:al2023
COPY bun-linux-x64-musl-static /usr/local/bin/bun
ENV SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
CMD ["/usr/local/bin/bun", "run", "index.ts"]
```

### Multi-stage Build

```dockerfile
FROM alpine:3.22 AS builder
WORKDIR /app
COPY package.json bun.lockb ./
RUN apk add --no-cache curl ca-certificates && \
    curl -fsSL https://bun.sh/install | bash && \
    /root/.bun/bin/bun install --frozen-lockfile

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /root/.bun/bin/bun /bun
COPY --from=builder /app/node_modules /app/node_modules
COPY . /app
WORKDIR /app
ENTRYPOINT ["/bun"]
CMD ["run", "index.ts"]
```

## Verification

### Verify Static Linking

```bash
# File type
file ./bun
# Output: ELF 64-bit LSB executable, x86-64, statically linked

# No dynamic dependencies
ldd ./bun
# Output: not a dynamic executable

# No NEEDED entries
readelf -d ./bun | grep NEEDED
# Output: (empty)

# No interpreter
readelf -l ./bun | grep interpreter
# Output: (empty)
```

### Automated Verification

```bash
./scripts/verify-static-musl.sh ./bun
```

### Test in Minimal Container

```bash
# Test in scratch-equivalent (BusyBox)
docker run --rm -v $(pwd)/bun:/bun:ro busybox:musl /bun --version

# Test across Alpine versions
for ver in 3.19 3.20 3.21 3.22; do
  echo "Testing on Alpine $ver:"
  docker run --rm -v $(pwd)/bun:/bun:ro alpine:$ver /bun --version
done
```

## Performance

Static builds have **minimal performance overhead**:

| Metric              | Static    | Dynamic   | Difference |
| ------------------- | --------- | --------- | ---------- |
| Startup time        | ~12ms     | ~10ms     | +2ms       |
| Runtime performance | Identical | Identical | 0%         |
| Memory usage        | Identical | Identical | 0%         |
| Binary size         | 105-110MB | ~100MB    | +5-10MB    |

The trade-off is worth it for deployment simplicity and portability.

## Troubleshooting

### Error: "certificate verify failed"

**Cause**: No CA certificates available

**Solution**:

```bash
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
bun run app.ts
```

Or install certificates in your container:

```dockerfile
RUN apk add ca-certificates  # Alpine
RUN apt-get install ca-certificates  # Debian/Ubuntu
```

### Error: "Illegal instruction" / Segfault

**Cause**: CPU doesn't support AVX2/AVX instructions

**Solution**: Use baseline build:

```bash
# Download baseline build (no AVX2 requirement)
curl -fsSL https://bun.sh/install-static-baseline | bash
```

Or build with baseline:

```bash
cmake -DABI=musl -DSTATIC_MUSL=ON -DENABLE_BASELINE=ON .
```

### Binary doesn't start

**Check kernel version**:

```bash
uname -r  # Must be 2.6.32 or newer
```

**Check architecture**:

```bash
uname -m  # Must match binary (x86_64 or aarch64)
file ./bun  # Verify binary architecture
```

### Network operations fail

1. **Check DNS resolution**:

   ```bash
   cat /etc/resolv.conf
   ping example.com
   ```

2. **Check CA certificates**:

   ```bash
   ls -la $SSL_CERT_FILE
   # or
   ls -la $SSL_CERT_DIR
   ```

3. **Enable debug logging**:
   ```bash
   BUN_DEBUG_QUIET_LOGS=0 bun run app.ts
   ```

### Still seeing dynamic dependencies

```bash
ldd bun  # Should say "not a dynamic executable"
```

If not, verify you built with `STATIC_MUSL=ON`:

```bash
grep "STATIC_MUSL" build/CMakeCache.txt
# Should show: STATIC_MUSL:BOOL=ON
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Setup Bun (static)
  run: |
    curl -fsSL https://bun.sh/install-static | bash
    echo "$HOME/.bun/bin" >> $GITHUB_PATH

- name: Install dependencies
  run: bun install

- name: Run tests
  run: bun test
  env:
    SSL_CERT_FILE: /etc/ssl/certs/ca-certificates.crt
```

### GitLab CI

```yaml
test:
  image: alpine:3.22
  before_script:
    - apk add ca-certificates curl bash
    - curl -fsSL https://bun.sh/install-static | sh
    - export PATH="$HOME/.bun/bin:$PATH"
  script:
    - bun install
    - bun test
```

### Buildkite

```yaml
steps:
  - label: "Test with static Bun"
    plugins:
      - docker#v5.11.0:
          image: alpine:3.22
    commands:
      - apk add ca-certificates curl bash
      - curl -fsSL https://bun.sh/install-static | bash
      - export PATH="$HOME/.bun/bin:$PATH"
      - bun install
      - bun test
```

## FAQ

**Q: Why use static builds instead of dynamic?**

A: Static builds work everywhere without requiring musl/glibc compatibility. Perfect for containers and cross-distro deployment.

**Q: Can I use `bun:ffi` in static builds?**

A: Limited support. Dynamic library loading may not work. Use dynamic builds if FFI is critical.

**Q: Are static builds slower?**

A: No meaningful difference. Startup is ~2ms slower (one-time cost), runtime performance is identical.

**Q: Which should I use: static or dynamic musl?**

A: Use static for maximum portability. Use dynamic if you need FFI or prefer smaller binaries (~5MB difference).

**Q: Do static builds work on glibc systems?**

A: Yes! Static musl builds run on both musl and glibc systems, even old glibc versions.

**Q: Can I cross-compile static builds?**

A: Yes, using the Zig toolchain and appropriate CMake toolchain file. See CONTRIBUTING.md for details.

**Q: Why is the binary larger?**

A: All libraries (libstdc++, libgcc, libatomic) are embedded in the binary instead of loaded dynamically.

## Related Documentation

- [Installation Guide](./installation.mdx)
- [Docker Deployment](./guides/docker.md)
- [AWS Lambda with Bun](./guides/lambda.md)
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Build instructions

## Support

Report issues: https://github.com/oven-sh/bun/issues

Tag with: `static-build`, `musl`
