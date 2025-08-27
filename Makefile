# Enigmo - Secure Messaging Platform
# Build automation and development workflows

.PHONY: help setup clean test format lint build-server build-app dev-server dev-app docker-up docker-down

# Default target
help: ## Show this help message
	@echo "🔐 Enigmo Development Commands"
	@echo "================================"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# Setup and Installation
setup: ## Install all dependencies for both app and server
	@echo "🚀 Setting up Enigmo development environment..."
	@echo "📱 Installing Flutter app dependencies..."
	cd enigmo_app && flutter pub get
	@echo "🖥️  Installing server dependencies..."
	cd enigmo_server && dart pub get
	@echo "✅ Setup complete!"

clean: ## Clean all build artifacts and caches
	@echo "🧹 Cleaning build artifacts..."
	cd enigmo_app && flutter clean
	cd enigmo_server && dart pub cache clean
	rm -rf build/
	@echo "✅ Clean complete!"

# Testing
test: ## Run all tests for both app and server
	@echo "🧪 Running all tests..."
	@echo "🖥️  Server tests..."
	cd enigmo_server && dart test --coverage
	@echo "📱 App tests..."
	cd enigmo_app && flutter test --coverage
	@echo "✅ All tests passed!"

test-server: ## Run only server tests
	@echo "🧪 Running server tests..."
	cd enigmo_server && dart test --coverage

test-app: ## Run only app tests
	@echo "🧪 Running app tests..."
	cd enigmo_app && flutter test --coverage

# Code Quality
format: ## Format all code
	@echo "🎨 Formatting code..."
	cd enigmo_server && dart format .
	cd enigmo_app && dart format .
	@echo "✅ Formatting complete!"

lint: ## Run static analysis
	@echo "🔍 Running static analysis..."
	cd enigmo_server && dart analyze
	cd enigmo_app && flutter analyze
	@echo "✅ Analysis complete!"

# Development
dev-server: ## Start server in development mode
	@echo "🖥️  Starting Enigmo server..."
	cd enigmo_server && dart run bin/anongram_server.dart --host localhost --port 8081 --debug

dev-app-ios: ## Start Flutter app on iOS
	@echo "📱 Starting Enigmo app on iOS..."
	cd enigmo_app && flutter run -d ios

dev-app-android: ## Start Flutter app on Android
	@echo "📱 Starting Enigmo app on Android..."
	cd enigmo_app && flutter run -d android

dev-app-web: ## Start Flutter app on Web
	@echo "🌐 Starting Enigmo app on Web..."
	cd enigmo_app && flutter run -d web

# Building
build-server: ## Build server executable
	@echo "🔨 Building server executable..."
	cd enigmo_server && dart compile exe bin/anongram_server.dart -o ../build/enigmo-server
	@echo "✅ Server built: build/enigmo-server"

build-app-android: ## Build Android APK
	@echo "🔨 Building Android APK..."
	cd enigmo_app && flutter build apk --release
	@echo "✅ Android APK built: enigmo_app/build/app/outputs/apk/release/"

build-app-android-bundle: ## Build Android App Bundle
	@echo "🔨 Building Android App Bundle..."
	cd enigmo_app && flutter build appbundle --release
	@echo "✅ Android Bundle built: enigmo_app/build/app/outputs/bundle/release/"

build-app-ios: ## Build iOS app
	@echo "🔨 Building iOS app..."
	cd enigmo_app && flutter build ios --release
	@echo "✅ iOS app built: enigmo_app/build/ios/iphoneos/"

build-app-web: ## Build web app
	@echo "🔨 Building web app..."
	cd enigmo_app && flutter build web --release
	@echo "✅ Web app built: enigmo_app/build/web/"

build-all: build-server build-app-android build-app-ios build-app-web ## Build all platforms

# Docker
docker-up: ## Start development environment with Docker
	@echo "🐳 Starting Docker development environment..."
	docker-compose up -d
	@echo "✅ Docker environment ready!"

docker-down: ## Stop Docker development environment
	@echo "🐳 Stopping Docker development environment..."
	docker-compose down
	@echo "✅ Docker environment stopped!"

docker-logs: ## View Docker logs
	docker-compose logs -f

# Release
release-check: test lint ## Pre-release checks
	@echo "🚀 Running pre-release checks..."
	@echo "✅ Ready for release!"

# Git helpers
git-setup: ## Setup git hooks and configuration
	@echo "🔧 Setting up git hooks..."
	cp scripts/pre-commit .git/hooks/
	chmod +x .git/hooks/pre-commit
	@echo "✅ Git hooks configured!"

# Health checks
health-check: ## Check if server is running and healthy
	@echo "🏥 Checking server health..."
	curl -f http://localhost:8081/api/health || echo "❌ Server not running"

stats: ## Show server statistics
	@echo "📊 Server statistics:"
	curl -s http://localhost:8081/api/stats | python3 -m json.tool

# Development tools
deps-update: ## Update all dependencies
	@echo "🔄 Updating dependencies..."
	cd enigmo_server && dart pub upgrade
	cd enigmo_app && flutter pub upgrade
	@echo "✅ Dependencies updated!"

deps-check: ## Check for outdated dependencies
	@echo "🔍 Checking for outdated dependencies..."
	cd enigmo_server && dart pub outdated
	cd enigmo_app && flutter pub outdated
