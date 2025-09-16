# NocoDB Deployment Makefile
# Удобные команды для управления проектом

.PHONY: help setup start stop restart logs status clean backup restore update

# Цвета для вывода
GREEN=\033[0;32m
YELLOW=\033[1;33m
RED=\033[0;31m
NC=\033[0m # No Color

# Переменные
COMPOSE_FILE = compose.yml
ENV_FILE = .env
NETWORK_NAME = nocodb

help: ## Показать справку по командам
	@echo "$(GREEN)NocoDB Deployment - Доступные команды:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

setup: ## Первоначальная настройка проекта
	@echo "$(GREEN)Настройка проекта NocoDB...$(NC)"
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "$(YELLOW)Создание файла .env...$(NC)"; \
		cp .env.example .env 2>/dev/null || echo "$(RED)Создайте файл .env на основе .env.example$(NC)"; \
	fi
	@echo "$(YELLOW)Создание Docker сети...$(NC)"
	@docker network create $(NETWORK_NAME) 2>/dev/null || echo "$(YELLOW)Сеть $(NETWORK_NAME) уже существует$(NC)"
	@echo "$(GREEN)Настройка завершена!$(NC)"
	@echo "$(YELLOW)Не забудьте настроить переменные в файле .env$(NC)"

start: ## Запустить все сервисы
	@echo "$(GREEN)Запуск сервисов NocoDB...$(NC)"
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "$(GREEN)Сервисы запущены!$(NC)"
	@echo "$(YELLOW)NocoDB доступен по адресу: http://localhost:8080$(NC)"

stop: ## Остановить все сервисы
	@echo "$(YELLOW)Остановка сервисов...$(NC)"
	@docker compose -f $(COMPOSE_FILE) down
	@echo "$(GREEN)Сервисы остановлены$(NC)"

restart: ## Перезапустить все сервисы
	@echo "$(YELLOW)Перезапуск сервисов...$(NC)"
	@docker compose -f $(COMPOSE_FILE) restart
	@echo "$(GREEN)Сервисы перезапущены$(NC)"

logs: ## Показать логи всех сервисов
	@docker compose -f $(COMPOSE_FILE) logs -f

logs-nocodb: ## Показать логи только NocoDB
	@docker compose -f $(COMPOSE_FILE) logs -f nocodb

logs-mysql: ## Показать логи только MySQL
	@docker compose -f $(COMPOSE_FILE) logs -f mysql

status: ## Показать статус сервисов
	@echo "$(GREEN)Статус сервисов:$(NC)"
	@docker compose -f $(COMPOSE_FILE) ps

status-detailed: ## Показать детальный статус с ресурсами
	@echo "$(GREEN)Детальный статус сервисов:$(NC)"
	@docker compose -f $(COMPOSE_FILE) ps
	@echo ""
	@echo "$(GREEN)Использование ресурсов:$(NC)"
	@docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $$(docker compose -f $(COMPOSE_FILE) ps -q)

clean: ## Остановить и удалить все контейнеры, тома и сети
	@echo "$(RED)ВНИМАНИЕ: Это удалит ВСЕ данные!$(NC)"
	@read -p "Вы уверены? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "$(YELLOW)Остановка и удаление сервисов...$(NC)"
	@docker compose -f $(COMPOSE_FILE) down -v --remove-orphans
	@echo "$(GREEN)Очистка завершена$(NC)"

clean-volumes: ## Удалить только тома данных (сохранить контейнеры)
	@echo "$(RED)ВНИМАНИЕ: Это удалит ВСЕ данные!$(NC)"
	@read -p "Вы уверены? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "$(YELLOW)Удаление томов данных...$(NC)"
	@docker volume rm nocodb_data mysql_data 2>/dev/null || echo "$(YELLOW)Тома уже удалены или не существуют$(NC)"
	@echo "$(GREEN)Тома удалены$(NC)"

backup: ## Создать резервную копию базы данных
	@echo "$(GREEN)Создание резервной копии...$(NC)"
	@mkdir -p backups
	@docker exec mysql mysqldump -u root -p$$(grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2) $$(grep MYSQL_DATABASE .env | cut -d '=' -f2) > backups/backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)Резервная копия создана в папке backups/$(NC)"

restore: ## Восстановить базу данных из резервной копии
	@echo "$(YELLOW)Доступные резервные копии:$(NC)"
	@ls -la backups/*.sql 2>/dev/null || echo "$(RED)Резервные копии не найдены$(NC)"
	@echo ""
	@read -p "Введите имя файла резервной копии: " backup_file; \
	if [ -f "backups/$$backup_file" ]; then \
		echo "$(GREEN)Восстановление из $$backup_file...$(NC)"; \
		docker exec -i mysql mysql -u root -p$$(grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2) $$(grep MYSQL_DATABASE .env | cut -d '=' -f2) < "backups/$$backup_file"; \
		echo "$(GREEN)Восстановление завершено$(NC)"; \
	else \
		echo "$(RED)Файл не найден$(NC)"; \
	fi

update: ## Обновить образы Docker
	@echo "$(GREEN)Обновление образов Docker...$(NC)"
	@docker compose -f $(COMPOSE_FILE) pull
	@echo "$(GREEN)Образы обновлены$(NC)"
	@echo "$(YELLOW)Для применения обновлений выполните: make restart$(NC)"

update-and-restart: ## Обновить образы и перезапустить сервисы
	@echo "$(GREEN)Обновление и перезапуск...$(NC)"
	@docker compose -f $(COMPOSE_FILE) pull
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "$(GREEN)Обновление и перезапуск завершены$(NC)"

shell-nocodb: ## Подключиться к контейнеру NocoDB
	@docker exec -it nocodb sh

shell-mysql: ## Подключиться к контейнеру MySQL
	@docker exec -it mysql mysql -u root -p$$(grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2)

health: ## Проверить состояние сервисов
	@echo "$(GREEN)Проверка состояния сервисов:$(NC)"
	@echo ""
	@echo "$(YELLOW)NocoDB:$(NC)"
	@curl -s -o /dev/null -w "HTTP Status: %{http_code}\nResponse Time: %{time_total}s\n" http://localhost:8080 || echo "$(RED)NocoDB недоступен$(NC)"
	@echo ""
	@echo "$(YELLOW)MySQL:$(NC)"
	@docker exec mysql mysqladmin ping -h localhost -u root -p$$(grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2) 2>/dev/null && echo "$(GREEN)MySQL работает$(NC)" || echo "$(RED)MySQL недоступен$(NC)"

monitor: ## Мониторинг ресурсов в реальном времени
	@echo "$(GREEN)Мониторинг ресурсов (Ctrl+C для выхода):$(NC)"
	@docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

dev: ## Запуск в режиме разработки с выводом логов
	@echo "$(GREEN)Запуск в режиме разработки...$(NC)"
	@docker compose -f $(COMPOSE_FILE) up

# Команда по умолчанию
.DEFAULT_GOAL := help
