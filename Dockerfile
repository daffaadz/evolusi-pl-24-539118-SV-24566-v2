# syntax=docker/dockerfile:1

# ==============================================================================
# STAGE 1: BUILDER
# Tahap membangun. Boleh besar: Composer, compiler ekstensi, header library.
# Tidak ikut ke image akhir.
# ==============================================================================
FROM php:8.4.26-cli-alpine3.24 AS builder

# Dependensi sistem untuk membangun ekstensi PHP dan menjalankan Composer
RUN apk add --no-cache \
    git \
    unzip \
    libzip-dev \
    sqlite-dev \
    linux-headers \
    && docker-php-ext-install pdo_mysql pdo_sqlite zip bcmath

# Composer binary dengan versi dikunci
COPY --from=composer:2.8 /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www/html

# DOCKER LAYER CACHING: file dependensi disalin dan dipasang SEBELUM kode aplikasi
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

# Salin seluruh kode aplikasi (kecuali yang ada di .dockerignore)
COPY . .

# Autoloader teroptimasi setelah kode aplikasi disalin
RUN composer dump-autoload --optimize

# Siapkan .env dari .env.example dan generate APP_KEY
RUN cp -n .env.example .env && \
    php artisan key:generate


# ==============================================================================
# STAGE 2: RUNTIME
# Tahap menjalankan. Hanya berisi yang dibutuhkan saat melayani request:
# PHP + ekstensi hasil build + library runtime + kode aplikasi.
# Tanpa Composer, git, unzip, header, dan compiler.
# ==============================================================================
FROM php:8.4.26-cli-alpine3.24 AS runtime

# Hanya library runtime (tanpa paket -dev)
RUN apk add --no-cache \
    libzip \
    sqlite-libs

# Ambil ekstensi PHP yang sudah dikompilasi dari builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

WORKDIR /var/www/html

# Ambil aplikasi lengkap (vendor + kode + .env) dari builder
COPY --from=builder /var/www/html /var/www/html

# Izin tulis untuk storage, bootstrap/cache, dan database
RUN chmod -R 775 storage bootstrap/cache database

# Container TIDAK boleh berjalan sebagai root: pakai www-data (bawaan image)
# dan beri kepemilikan hanya pada direktori yang perlu ditulis.
RUN chown -R www-data:www-data storage bootstrap/cache database
USER www-data

EXPOSE 8000

# HEALTHCHECK memakai route /up bawaan Laravel (wget tersedia di busybox alpine)
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8000/up || exit 1

CMD ["sh", "-c", "touch database/database.sqlite && php artisan migrate --force && php artisan serve --host=0.0.0.0 --port=8000"]
