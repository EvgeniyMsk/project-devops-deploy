test:
	./gradlew test

start: run

run:
	./gradlew bootRun

update-gradle:
	./gradlew wrapper --gradle-version 9.2.1

update-deps:
	./gradlew refreshVersions

install:
	./gradlew dependencies

build:
	./gradlew build

lint:
	./gradlew spotlessCheck

lint-fix:
	./gradlew spotlessApply

DOCKER_IMAGE ?= project-devops-deploy
DOCKER_TAG ?= latest

docker-build:
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

docker-run:
	docker run --rm -p 8080:8080 -p 9090:9090 $(DOCKER_IMAGE):$(DOCKER_TAG)

docker-start: docker-build docker-run

setup:
ifneq ($(strip $(VAULT_PASS_FILE)),)
	ansible-playbook playbook.yml --vault-password-file $(VAULT_PASS_FILE)
else
	ansible-playbook playbook.yml --ask-vault-pass
endif

deploy:
ifneq ($(strip $(VAULT_PASS_FILE)),)
	ansible-playbook playbook.yml -t deploy --vault-password-file $(VAULT_PASS_FILE)
else
	ansible-playbook playbook.yml -t deploy --ask-vault-pass
endif

.PHONY: test start run update-gradle update-deps install build lint lint-fix docker-build docker-run docker-start setup deploy
