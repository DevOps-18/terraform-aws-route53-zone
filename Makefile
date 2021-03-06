ifneq (,)
.error This Makefile requires GNU Make.
endif

CURRENT_DIR = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TF_EXAMPLES = $(sort $(dir $(wildcard $(CURRENT_DIR)examples/*/)))


# -------------------------------------------------------------------------------------------------
# Image versions
# -------------------------------------------------------------------------------------------------
TF_VERSION      = light
TFDOCS_VERSION  = latest
FL_VERSION      = 0.4


# -------------------------------------------------------------------------------------------------
# Image settings
# -------------------------------------------------------------------------------------------------
# Adjust your delimiter here or overwrite via make arguments
DELIM_START = <!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
DELIM_CLOSE = <!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
# What arguments to append to terraform-docs command
TFDOCS_ARGS = --sort-by-required

FL_IGNORE = .git/,.github/,*.terraform/

# -------------------------------------------------------------------------------------------------
# Default target
# -------------------------------------------------------------------------------------------------
help:
	@echo "gen        Generate terraform-docs output and replace in README.md's"
	@echo "lint       Static source code analysis"
	@echo "test       Integration tests"


# -------------------------------------------------------------------------------------------------
# Standard targets
# -------------------------------------------------------------------------------------------------
gen: _pull-tfdocs
	@echo "################################################################################"
	@echo "# Terraform-docs generate"
	@echo "################################################################################"
	@$(MAKE) --no-print-directory _gen-main
	@$(MAKE) --no-print-directory _gen-examples

lint:
	@# Lint all Terraform files
	@echo "################################################################################"
	@echo "# Linting"
	@echo "################################################################################"
	$(MAKE) --no-print-directory _lint-files
	$(MAKE) --no-print-directory _lint-fmt

	@if docker run -it --rm -v "$(CURRENT_DIR):/t:ro" --workdir "/t" hashicorp/terraform:light \
		fmt -check=true -diff=true -write=false -list=true .; then \
		echo "OK"; \
	else \
		echo "Failed"; \
		exit 1; \
	fi;
	@echo


test: _pull-tf
	@$(foreach example,\
		$(TF_EXAMPLES),\
		DOCKER_PATH="/t/examples/$(notdir $(patsubst %/,%,$(example)))"; \
		echo "################################################################################"; \
		echo "# Terraform init:  $${DOCKER_PATH}"; \
		echo "################################################################################"; \
		if docker run -it --rm -v "$(CURRENT_DIR):/t" --workdir "$${DOCKER_PATH}" hashicorp/terraform:light \
			init \
				-verify-plugins=true \
				-lock=false \
				-upgrade=true \
				-reconfigure \
				-input=false \
				-get-plugins=true \
				-get=true \
				.; then \
			echo "OK"; \
		else \
			echo "Failed"; \
			docker run -it --rm -v "$(CURRENT_DIR):/t" --workdir "$${DOCKER_PATH}" --entrypoint=rm hashicorp/terraform:light -rf .terraform/ || true; \
			exit 1; \
		fi; \
		echo; \
	)
	@$(foreach example,\
		$(TF_EXAMPLES),\
		DOCKER_PATH="/t/examples/$(notdir $(patsubst %/,%,$(example)))"; \
		echo "################################################################################"; \
		echo "# Terraform validate:  $${DOCKER_PATH}"; \
		echo "################################################################################"; \
		if docker run -it --rm -v "$(CURRENT_DIR):/t" --workdir "$${DOCKER_PATH}" hashicorp/terraform:light \
			validate \
				.; then \
			echo "OK"; \
			docker run -it --rm -v "$(CURRENT_DIR):/t" --workdir "$${DOCKER_PATH}" --entrypoint=rm hashicorp/terraform:light -rf .terraform/ || true; \
		else \
			echo "Failed"; \
			docker run -it --rm -v "$(CURRENT_DIR):/t" --workdir "$${DOCKER_PATH}" --entrypoint=rm hashicorp/terraform:light -rf .terraform/ || true; \
			exit 1; \
		fi; \
		echo; \
	)


# -------------------------------------------------------------------------------------------------
# Helper Targets
# -------------------------------------------------------------------------------------------------
_gen-main:
	@echo "------------------------------------------------------------"
	@echo "# Main module"
	@echo "------------------------------------------------------------"
	@if docker run --rm \
		-v $(CURRENT_DIR):/data \
		-e DELIM_START='$(DELIM_START)' \
		-e DELIM_CLOSE='$(DELIM_CLOSE)' \
		cytopia/terraform-docs:$(TFDOCS_VERSION) \
		terraform-docs-replace-012 $(TFDOCS_ARGS) md README.md; then \
		echo "OK"; \
	else \
		echo "Failed"; \
		exit 1; \
	fi

_gen-examples:
	@$(foreach example,\
		$(TF_EXAMPLES),\
		DOCKER_PATH="examples/$(notdir $(patsubst %/,%,$(example)))"; \
		echo "------------------------------------------------------------"; \
		echo "# $${DOCKER_PATH}"; \
		echo "------------------------------------------------------------"; \
		if docker run --rm \
			-v $(CURRENT_DIR):/data \
			-e DELIM_START='$(DELIM_START)' \
			-e DELIM_CLOSE='$(DELIM_CLOSE)' \
			cytopia/terraform-docs:$(TFDOCS_VERSION) \
			terraform-docs-replace-012 $(TFDOCS_ARGS) md $${DOCKER_PATH}/README.md; then \
			echo "OK"; \
		else \
			echo "Failed"; \
			exit 1; \
		fi; \
	)

_lint-files: _pull-fl
	@# Basic file linting
	@echo "################################################################################"
	@echo "# File-lint"
	@echo "################################################################################"
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint:$(FL_VERSION) file-cr --text --ignore '$(FL_IGNORE)' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint:$(FL_VERSION) file-crlf --text --ignore '$(FL_IGNORE)' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint:$(FL_VERSION) file-trailing-single-newline --text --ignore '$(FL_IGNORE)' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint:$(FL_VERSION) file-trailing-space --text --ignore '$(FL_IGNORE)' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint:$(FL_VERSION) file-utf8 --text --ignore '$(FL_IGNORE)' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint:$(FL_VERSION) file-utf8-bom --text --ignore '$(FL_IGNORE)' --path .

_lint-fmt: _pull-tf
	@# Lint all Terraform files
	@echo "################################################################################"
	@echo "# Terraform fmt"
	@echo "################################################################################"
	@echo
	@echo "------------------------------------------------------------"
	@echo "# *.tf files"
	@echo "------------------------------------------------------------"
	@if docker run -it --rm -v "$(CURRENT_DIR):/t:ro" --workdir "/t" hashicorp/terraform:$(TF_VERSION) \
		fmt -check=true -diff=true -write=false -list=true .; then \
		echo "OK"; \
	else \
		echo "Failed"; \
		exit 1; \
	fi;
	@echo
	@echo "------------------------------------------------------------"
	@echo "# *.tfvars files"
	@echo "------------------------------------------------------------"
	@if docker run --rm --entrypoint=/bin/sh -v "$(CURRENT_DIR):/t:ro" --workdir "/t" hashicorp/terraform:$(TF_VERSION) \
		-c "find . -name '*.tfvars' -type f -print0 | xargs -0 -n1 terraform fmt -check=true -write=false -diff=true -list=true"; then \
		echo "OK"; \
	else \
		echo "Failed"; \
		exit 1; \
	fi;
	@echo

_pull-tf:
	docker pull hashicorp/terraform:$(TF_VERSION)

_pull-tfdocs:
	docker pull cytopia/terraform-docs:$(TFDOCS_VERSION)

_pull-fl:
	docker pull cytopia/file-lint:$(FL_VERSION)
