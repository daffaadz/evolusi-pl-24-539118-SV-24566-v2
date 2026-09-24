FROM php:8.4-cli-alpine

# Install system dependencies and required PHP extension libraries
RUN apk add --no-cache \
    git \
    unzip \
    libzip-dev \
    sqlite-dev \
    linux-headers \
    && docker-php-ext-install pdo_mysql pdo_sqlite zip bcmath

# Install Composer binary from official Composer image
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Set working directory inside container
WORKDIR /var/www/html

# DOCKER LAYER CACHING
COPY composer.json composer.lock ./

# Pasang dependensi PHP tanpa dev dependencies & scripts
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

# Salin seluruh berkas kode aplikasi (kecuali di .dockerignore)
COPY . .

# Generate autoloader teroptimasi setelah kode aplikasi disalin
RUN composer dump-autoload --optimize

# Salin konfigurasi environment dari .env.example dan generate APP_KEY
RUN cp -n .env.example .env && \
    php artisan key:generate

# Berikan izin tulis untuk storage, bootstrap/cache, dan database
RUN chmod -R 775 storage bootstrap/cache database

# Expose port aplikasi Laravel
EXPOSE 8000

# Jalankan migrasi database saat container dinyalakan dan jalankan server Laravel
CMD ["sh", "-c", "touch database/database.sqlite && php artisan migrate --force && php artisan serve --host=0.0.0.0 --port=8000"]

