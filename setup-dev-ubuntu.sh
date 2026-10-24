#!/usr/bin/env bash
# setup-dev-ubuntu.sh
# Development environment bootstrap for Ubuntu 24.04 (and Ubuntu-based distros).
# Bootstrap de ambiente de desenvolvimento para Ubuntu 24.04 (e derivados do Ubuntu).
#
# You choose WHAT to install (each item is explained) and, optionally, WHICH VERSION.
# Versions accept partial input: "24", "24.20", "lts", "krypton", "27.3", "3.13"...
# Você escolhe O QUE instalar (cada item é explicado) e, se quiser, QUAL VERSÃO.
# As versões aceitam entrada parcial: "24", "24.20", "lts", "krypton", "27.3", "3.13"...
#
# Usage / Uso:
#   bash setup-dev-ubuntu.sh [--lang en-US|pt-BR] [--components a,b,c] [--yes] [--help]
#
# Run as a normal user (NOT with sudo). It calls sudo when needed.
# Rode como usuário normal (SEM sudo). Ele chama o sudo quando precisar.
# Safe to re-run: anything already installed is skipped.

set -euo pipefail

# ===============================================================
# CONFIG / CONFIGURAÇÃO  (everything can be overridden via environment variables)
# ===============================================================
# Version requests. Free-form text, resolved against what is really available.
NODE_VERSION="${NODE_VERSION:-lts}"          # 24 | 24.20 | 24.20.0 | lts | krypton | latest
DOCKER_VERSION="${DOCKER_VERSION:-latest}"   # 27 | 27.3 | 27.3.1 | latest
CODE_VERSION="${CODE_VERSION:-latest}"       # 1.105 | latest
GH_VERSION="${GH_VERSION:-latest}"           # 2.62 | latest
PYTHON_VERSION="${PYTHON_VERSION:-system}"   # system | 3.13 | 3.12 ...
NVM_VERSION="${NVM_VERSION:-latest}"         # latest | v0.40.8 ...
NVM_FALLBACK="v0.40.8"                       # used if "latest" cannot be looked up

GIT_NAME="${GIT_NAME:-}"                     # asked interactively if empty
GIT_EMAIL="${GIT_EMAIL:-}"                   # asked interactively if empty
SETUP_LANG="${SETUP_LANG:-}"                 # en-US | pt-BR (asked if empty)

# Default selection (true/false). The interactive menu starts from these values.
INSTALL_TERMINAL="${INSTALL_TERMINAL:-true}"
INSTALL_BASE_DEV="${INSTALL_BASE_DEV:-true}"
INSTALL_GIT="${INSTALL_GIT:-true}"
INSTALL_GH="${INSTALL_GH:-true}"
INSTALL_PYTHON="${INSTALL_PYTHON:-true}"
INSTALL_NODE="${INSTALL_NODE:-true}"
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"
INSTALL_VSCODE="${INSTALL_VSCODE:-true}"
GENERATE_SSH_KEY="${GENERATE_SSH_KEY:-true}" # offered only if a Git email is provided

# VS Code extensions (extension ids). Edit freely.
VSCODE_EXTENSIONS=(
  ms-python.python
  dbaeumer.vscode-eslint
  esbenp.prettier-vscode
  ms-azuretools.vscode-docker
  eamodio.gitlens
)

# ===============================================================
# Internal state
# ===============================================================
export DEBIAN_FRONTEND=noninteractive
ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
EMAIL_RE='^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
NODE_INDEX_URL="https://nodejs.org/dist/index.json"

LANG_CODE="en-US"
INTERACTIVE=false
ASSUME_YES=false
SHOW_HELP=false
COMPONENTS_ARG=""
DO_SSH=false
SSH_EXISTS=false
SUDO_KEEPALIVE_PID=""
PREREQS_DONE=false
REPO_ADDED=false
NVM_RESOLVED=""
NODE_CATALOG=""
TMP_FILES=()

COMPONENTS=(terminal base git gh python node docker vscode)
VERSIONED=(gh python node docker vscode)

declare -A SEL=(
  [terminal]="$INSTALL_TERMINAL" [base]="$INSTALL_BASE_DEV" [git]="$INSTALL_GIT"
  [gh]="$INSTALL_GH" [python]="$INSTALL_PYTHON" [node]="$INSTALL_NODE"
  [docker]="$INSTALL_DOCKER" [vscode]="$INSTALL_VSCODE"
)
declare -A VSPEC=(
  [gh]="$GH_VERSION" [python]="$PYTHON_VERSION" [node]="$NODE_VERSION"
  [docker]="$DOCKER_VERSION" [vscode]="$CODE_VERSION"
)
declare -A VLABEL=(
  [gh]="GitHub CLI" [python]="Python" [node]="Node.js"
  [docker]="Docker Engine" [vscode]="Visual Studio Code"
)
declare -A VEXACT=() VPIN=() VINFO=()
for _id in "${VERSIONED[@]}"; do VEXACT[$_id]=""; VPIN[$_id]=false; VINFO[$_id]=""; done
unset _id

# ===============================================================
# Messages / Mensagens
# ===============================================================
declare -A MSG_EN MSG_PT

MSG_EN=(
  [intro_title]="Set up a development environment on Ubuntu. First you choose what to install; then, if you want, the versions."
  [intro_note]="It uses sudo, backs up your existing ~/.zshrc, and skips what is already installed."
  [no_root]="Do not run this as root. Run it as your normal user; the script calls sudo when needed."
  [no_apt]="This script targets Ubuntu and Ubuntu-based distros (it needs apt)."
  [non_interactive]="No terminal detected: using defaults and environment variables (SETUP_LANG, GIT_NAME, GIT_EMAIL, *_VERSION)."
  [aborted]="Aborted. Nothing was installed."
  [aborted_repos]="Note: apt repositories were already added under /etc/apt/sources.list.d/. Remove them if you do not want them."
  [sel_title]="Choose what to install"
  [sel_help]="Type the numbers to toggle (e.g. 2 5), 'all', 'none', or just press Enter to continue."
  [sel_invalid]="Not a valid choice: %s"
  [sel_none]="Nothing selected. Nothing to do."
  [comp_unknown]="Unknown component: %s (valid: %s)"
  [lbl_what]="What"
  [lbl_why]="Why"
  [tag_installed]="installed: %s"

  [c_terminal_name]="Shell experience (zsh + Oh My Zsh + Powerlevel10k)"
  [c_terminal_what]="zsh as your default shell with the Oh My Zsh framework, autosuggestions, syntax highlighting, a live completion menu, the Powerlevel10k prompt theme, the MesloLGS NF icon font and a system-info welcome message (fastfetch)."
  [c_terminal_why]="Faster and safer command-line work: it suggests commands from your history, highlights typos before you press Enter and shows Git status right in the prompt."
  [c_base_name]="Base build tools and CLI utilities"
  [c_base_what]="build-essential (gcc, make), pkg-config, libssl-dev, jq, ripgrep, fd, bat, htop and tree."
  [c_base_why]="Node and Python packages often compile native code and need a compiler; the CLI tools make searching files, reading JSON and monitoring the machine much faster."
  [c_git_name]="Git identity and SSH key"
  [c_git_what]="Sets your commit name and email, makes 'main' the default branch and can create an SSH key for GitHub."
  [c_git_why]="Needed to sign your commits with your name and to push to GitHub without typing a password."
  [c_gh_name]="GitHub CLI (gh)"
  [c_gh_what]="GitHub's official command-line tool: repositories, pull requests, issues, gists and login."
  [c_gh_why]="Log in once with 'gh auth login' and handle pull requests or create repositories without leaving the terminal. Version can be chosen."
  [c_python_name]="Python 3 (pip, venv, pipx)"
  [c_python_what]="python3 with pip, venv, development headers and pipx. Optionally a specific Python version installed side by side with the system one."
  [c_python_why]="Scripting, automation, data and AI work. Linux tools depend on the system Python, so a specific version is added alongside it and never replaces it."
  [c_node_name]="Node.js via nvm (+ npm)"
  [c_node_what]="nvm installs and switches Node.js versions per project. npm ships with Node, and corepack gives you pnpm and yarn."
  [c_node_why]="Web frameworks, TypeScript and a huge number of dev CLIs run on Node. nvm avoids sudo and version clashes between projects. Version can be chosen."
  [c_docker_name]="Docker Engine + Compose"
  [c_docker_what]="The container runtime from Docker's official repository, with the Buildx and Compose plugins."
  [c_docker_why]="Run databases and services in containers, reproduce production setups and start whole stacks with 'docker compose up'. Version can be chosen."
  [c_vscode_name]="Visual Studio Code"
  [c_vscode_what]="Microsoft's code editor from the official repository, plus a list of extensions that you can edit at the top of the script."
  [c_vscode_why]="A popular, extensible editor with strong support for JavaScript, Python, Docker and Git. Version can be chosen."

  [ask_versions]="Do you want to pick specific versions? (default: the latest stable version of everything)"
  [ver_hint]="%s: press Enter for '%s', type a version number or name (e.g. %s), or type 'list' to see what is available."
  [ver_list_title]="Available versions (newest first):"
  [ver_none]="No versions found. Is the repository reachable?"
  [ver_no_match]="No version matches '%s'. Some available ones:"
  [ver_resolved]="'%s' resolved to: %s"
  [ver_fail]="Could not resolve the %s version '%s'."
  [ver_ex_node]="24, 24.20, lts, krypton, latest"
  [ver_ex_docker]="27, 27.3, 27.3.1, latest"
  [ver_ex_vscode]="1.105, latest"
  [ver_ex_gh]="2.62, latest"
  [ver_ex_python]="3.13, 3.12, system"
  [node_offline]="Could not reach nodejs.org to validate versions; '%s' will be passed straight to nvm."
  [nvm_fallback]="Could not look up the latest nvm release; using %s."
  [python_ppa]="Python %s is not in the default repositories; adding the deadsnakes PPA."
  [python_unavailable]="Python %s is not available."
  [python_list_note]="Other versions (e.g. 3.13) come from the deadsnakes PPA, which is added automatically when you type them."
  [python_extra]="Python %s installed alongside the system Python (it does not replace it). Use: python%s -m venv .venv"
  [repo_prep]="Adding the %s apt repository to read available versions"
  [prereqs]="Installing prerequisites (curl, gnupg, software-properties-common)"
  [installed_keep]="%s is already installed (%s); keeping it."
  [plan_title]="Plan:"
  [plan_latest]="latest"
  [plan_pinned]="pinned"
  [plan_kept]="already installed, kept"
  [ask_proceed]="Proceed with the installation?"
  [pin_hold]="Pinned version: apt hold applied to %s (undo with: sudo apt-mark unhold %s)."

  [git_intro]="Git identity (used to sign your commits). Press Enter to accept the value in brackets, or leave empty to skip."
  [git_name_prompt]="Git name"
  [git_email_prompt]="Git email"
  [git_email_invalid]="That does not look like a valid email. Try again, or leave it empty to skip."
  [ssh_ask]="Generate an SSH key for GitHub? (you will be asked for a passphrase at the end)"
  [hint_yn]="[Y/n]"
  [hint_ny]="[y/N]"
  [sudo_prompt]="Asking for your sudo password once so the install can run unattended"
  [base_update]="Updating apt and installing base packages"
  [base_dev]="Installing build tools and utilities"
  [fastfetch_already]="fastfetch already installed, skipping"
  [fastfetch_install]="Installing fastfetch"
  [fastfetch_fallback]="Not available in apt, downloading the .deb from GitHub..."
  [fastfetch_arch]="No fastfetch fallback for this architecture: %s"
  [omz_already]="Oh My Zsh already installed, skipping"
  [omz_install]="Installing Oh My Zsh"
  [plugins_clone]="Cloning plugins and theme"
  [font_install]="Installing MesloLGS NF font"
  [font_gnome]="GNOME Terminal font configured."
  [font_manual]="Set the 'MesloLGS NF' font in your terminal preferences."
  [zshrc_write]="Writing ~/.zshrc"
  [zshrc_backup]="Backup saved to %s"
  [shell_set]="Setting zsh as the default shell"
  [shell_done]="Default shell changed to %s"
  [shell_already]="zsh is already the default shell"
  [python_install]="Installing Python 3, pip, venv and pipx"
  [node_install]="Installing nvm %s and Node.js (%s)"
  [nvm_already]="nvm already installed, skipping"
  [corepack_warn]="corepack not enabled (fine, install pnpm/yarn later if you need them)"
  [docker_already]="Docker already installed, skipping install"
  [docker_install]="Installing Docker Engine"
  [docker_service_warn]="Could not enable the Docker service via systemd."
  [docker_group]="User %s added to the docker group (takes effect after logout/login)."
  [vscode_already]="VS Code already installed, skipping install"
  [vscode_install]="Installing VS Code"
  [vscode_ext]="Installing VS Code extensions"
  [ext_ok]="ok: %s"
  [ext_fail]="failed: %s (install it later from inside VS Code)"
  [gh_already]="GitHub CLI already installed, skipping"
  [gh_install]="Installing GitHub CLI"
  [git_config]="Configuring Git"
  [git_skip_warn]="Git name/email not set. Later, run: git config --global user.name / user.email"
  [ssh_generating]="Generating SSH key (it will ask for a passphrase; leaving it empty is allowed)"
  [ssh_exists]="SSH key already exists, skipping"
  [ssh_pub]="Public key (paste it at github.com/settings/keys):"
  [summary_title]="Installed versions"
  [final_title]="What is left:"
  [final_1]="1. Log out and back in (or reboot). This activates zsh as default and the docker group (docker without sudo)."
  [final_2]="2. Open a terminal. On first launch Powerlevel10k starts its wizard (or run: p10k configure)."
  [final_3]="3. If icons look broken, set your terminal font to 'MesloLGS NF'."
  [final_4]="4. Test Docker:  docker run hello-world"
  [final_5]="5. Log in to GitHub:  gh auth login"
  [final_tip]="Tip: keep ~/.p10k.zsh next to this script (dotfiles repo) and copy it back before opening the terminal after a reinstall to skip the wizard. Put tokens and secrets in ~/.zshrc.local, never in a script."
  [L_user]="User"
  [L_system]="System"
  [L_ram]="RAM"
  [L_disk]="Disk"
  [L_uptime]="Uptime"
  [L_used_of]="used of"
  [help]="Usage: bash setup-dev-ubuntu.sh [options]\n\nOptions:\n  --lang <en-US|pt-BR>    Choose the language (skips the menu)\n  --components <list>     Comma-separated: terminal,base,git,gh,python,node,docker,vscode\n                          (skips the selection menu)\n  -y, --yes               Do not ask questions; use defaults and environment variables\n  -h, --help              Show this help\n\nEnvironment variables:\n  SETUP_LANG, GIT_NAME, GIT_EMAIL\n  NODE_VERSION, DOCKER_VERSION, CODE_VERSION, GH_VERSION, PYTHON_VERSION, NVM_VERSION\n  INSTALL_<COMPONENT>=true|false   (e.g. INSTALL_DOCKER=false)\n\nVersions accept partial input, e.g. NODE_VERSION=24 or DOCKER_VERSION=27.3\n"
)

MSG_PT=(
  [intro_title]="Configura um ambiente de desenvolvimento no Ubuntu. Primeiro você escolhe o que instalar; depois, se quiser, as versões."
  [intro_note]="Usa sudo, faz backup do seu ~/.zshrc atual e pula o que já estiver instalado."
  [no_root]="Não rode como root. Rode com seu usuário normal; o script chama o sudo quando precisar."
  [no_apt]="Este script é para Ubuntu e derivados do Ubuntu (precisa do apt)."
  [non_interactive]="Nenhum terminal detectado: usando padrões e variáveis de ambiente (SETUP_LANG, GIT_NAME, GIT_EMAIL, *_VERSION)."
  [aborted]="Cancelado. Nada foi instalado."
  [aborted_repos]="Obs.: repositórios apt já foram adicionados em /etc/apt/sources.list.d/. Remova-os se não quiser mantê-los."
  [sel_title]="Escolha o que instalar"
  [sel_help]="Digite os números para marcar/desmarcar (ex.: 2 5), 'all', 'none', ou só Enter para continuar."
  [sel_invalid]="Escolha inválida: %s"
  [sel_none]="Nada selecionado. Nada a fazer."
  [comp_unknown]="Componente desconhecido: %s (válidos: %s)"
  [lbl_what]="O que é"
  [lbl_why]="Por quê"
  [tag_installed]="instalado: %s"

  [c_terminal_name]="Experiência de shell (zsh + Oh My Zsh + Powerlevel10k)"
  [c_terminal_what]="zsh como shell padrão com o framework Oh My Zsh, sugestões automáticas, destaque de sintaxe, menu de autocompletar ao vivo, o tema Powerlevel10k, a fonte de ícones MesloLGS NF e uma mensagem de boas-vindas com info do sistema (fastfetch)."
  [c_terminal_why]="Trabalho na linha de comando mais rápido e seguro: sugere comandos do seu histórico, destaca erros de digitação antes do Enter e mostra o status do Git no prompt."
  [c_base_name]="Ferramentas de build e utilitários de linha de comando"
  [c_base_what]="build-essential (gcc, make), pkg-config, libssl-dev, jq, ripgrep, fd, bat, htop e tree."
  [c_base_why]="Pacotes Node e Python costumam compilar código nativo e precisam de compilador; os utilitários deixam buscar arquivos, ler JSON e monitorar a máquina bem mais rápido."
  [c_git_name]="Identidade do Git e chave SSH"
  [c_git_what]="Define nome e e-mail dos commits, deixa 'main' como branch padrão e pode criar uma chave SSH para o GitHub."
  [c_git_why]="Necessário para assinar seus commits com seu nome e para dar push no GitHub sem digitar senha."
  [c_gh_name]="GitHub CLI (gh)"
  [c_gh_what]="Ferramenta oficial do GitHub para a linha de comando: repositórios, pull requests, issues, gists e login."
  [c_gh_why]="Faça login uma vez com 'gh auth login' e trate pull requests ou crie repositórios sem sair do terminal. A versão pode ser escolhida."
  [c_python_name]="Python 3 (pip, venv, pipx)"
  [c_python_what]="python3 com pip, venv, headers de desenvolvimento e pipx. Opcionalmente uma versão específica do Python instalada ao lado da do sistema."
  [c_python_why]="Scripts, automação, dados e IA. Ferramentas do Linux dependem do Python do sistema, então a versão específica entra ao lado dele e nunca o substitui."
  [c_node_name]="Node.js via nvm (+ npm)"
  [c_node_what]="O nvm instala e troca versões do Node.js por projeto. O npm vem junto com o Node, e o corepack dá acesso ao pnpm e ao yarn."
  [c_node_why]="Frameworks web, TypeScript e uma enorme quantidade de CLIs de dev rodam em Node. O nvm evita sudo e conflito de versões entre projetos. A versão pode ser escolhida."
  [c_docker_name]="Docker Engine + Compose"
  [c_docker_what]="O runtime de contêineres do repositório oficial do Docker, com os plugins Buildx e Compose."
  [c_docker_why]="Rodar bancos de dados e serviços em contêineres, reproduzir o ambiente de produção e subir stacks inteiras com 'docker compose up'. A versão pode ser escolhida."
  [c_vscode_name]="Visual Studio Code"
  [c_vscode_what]="Editor de código da Microsoft pelo repositório oficial, mais uma lista de extensões que você edita no topo do script."
  [c_vscode_why]="Editor popular e extensível, com ótimo suporte a JavaScript, Python, Docker e Git. A versão pode ser escolhida."

  [ask_versions]="Quer escolher versões específicas? (padrão: a versão estável mais recente de tudo)"
  [ver_hint]="%s: Enter para '%s', digite um número ou nome de versão (ex.: %s), ou 'list' para ver as disponíveis."
  [ver_list_title]="Versões disponíveis (mais novas primeiro):"
  [ver_none]="Nenhuma versão encontrada. O repositório está acessível?"
  [ver_no_match]="Nenhuma versão combina com '%s'. Algumas disponíveis:"
  [ver_resolved]="'%s' resolvido para: %s"
  [ver_fail]="Não consegui resolver a versão de %s: '%s'."
  [node_offline]="Não consegui acessar nodejs.org para validar versões; '%s' será repassado direto ao nvm."
  [nvm_fallback]="Não consegui consultar a última versão do nvm; usando %s."
  [python_ppa]="O Python %s não está nos repositórios padrão; adicionando o PPA deadsnakes."
  [python_unavailable]="O Python %s não está disponível."
  [python_list_note]="Outras versões (ex.: 3.13) vêm do PPA deadsnakes, adicionado automaticamente quando você digita uma delas."
  [python_extra]="Python %s instalado ao lado do Python do sistema (não o substitui). Use: python%s -m venv .venv"
  [repo_prep]="Adicionando o repositório apt do %s para ler as versões disponíveis"
  [prereqs]="Instalando pré-requisitos (curl, gnupg, software-properties-common)"
  [installed_keep]="%s já está instalado (%s); mantendo."
  [plan_title]="Plano:"
  [plan_latest]="mais recente"
  [plan_pinned]="fixada"
  [plan_kept]="já instalado, mantido"
  [ask_proceed]="Prosseguir com a instalação?"
  [pin_hold]="Versão fixada: apt hold aplicado em %s (para desfazer: sudo apt-mark unhold %s)."

  [git_intro]="Identidade do Git (usada nos seus commits). Enter aceita o valor entre colchetes; deixe vazio para pular."
  [git_name_prompt]="Nome do Git"
  [git_email_prompt]="E-mail do Git"
  [git_email_invalid]="Isso não parece um e-mail válido. Tente de novo, ou deixe vazio para pular."
  [ssh_ask]="Gerar uma chave SSH para o GitHub? (vai pedir uma senha para a chave no final)"
  [hint_yn]="[S/n]"
  [hint_ny]="[s/N]"
  [sudo_prompt]="Pedindo a senha do sudo uma vez para a instalação rodar sem interrupções"
  [base_update]="Atualizando o apt e instalando pacotes base"
  [base_dev]="Instalando ferramentas de build e utilitários"
  [fastfetch_already]="fastfetch já instalado, pulando"
  [fastfetch_install]="Instalando fastfetch"
  [fastfetch_fallback]="Não achei no apt, baixando o .deb do GitHub..."
  [fastfetch_arch]="Sem fallback do fastfetch para esta arquitetura: %s"
  [omz_already]="Oh My Zsh já instalado, pulando"
  [omz_install]="Instalando Oh My Zsh"
  [plugins_clone]="Clonando plugins e tema"
  [font_install]="Instalando a fonte MesloLGS NF"
  [font_gnome]="Fonte do GNOME Terminal configurada."
  [font_manual]="Defina a fonte 'MesloLGS NF' nas preferências do seu terminal."
  [zshrc_write]="Escrevendo ~/.zshrc"
  [zshrc_backup]="Backup salvo em %s"
  [shell_set]="Definindo o zsh como shell padrão"
  [shell_done]="Shell padrão alterado para %s"
  [shell_already]="O zsh já é o shell padrão"
  [python_install]="Instalando Python 3, pip, venv e pipx"
  [node_install]="Instalando nvm %s e Node.js (%s)"
  [nvm_already]="nvm já instalado, pulando"
  [corepack_warn]="corepack não habilitado (tudo bem, instale pnpm/yarn depois se precisar)"
  [docker_already]="Docker já instalado, pulando a instalação"
  [docker_install]="Instalando Docker Engine"
  [docker_service_warn]="Não consegui habilitar o serviço do Docker via systemd."
  [docker_group]="Usuário %s adicionado ao grupo docker (vale depois de logout/login)."
  [vscode_already]="VS Code já instalado, pulando a instalação"
  [vscode_install]="Instalando VS Code"
  [vscode_ext]="Instalando extensões do VS Code"
  [ext_ok]="ok: %s"
  [ext_fail]="falhou: %s (instale depois pelo VS Code)"
  [gh_already]="GitHub CLI já instalado, pulando"
  [gh_install]="Instalando GitHub CLI"
  [git_config]="Configurando o Git"
  [git_skip_warn]="Nome/e-mail do Git não definidos. Depois, rode: git config --global user.name / user.email"
  [ssh_generating]="Gerando chave SSH (vai pedir uma senha; deixar vazio é permitido)"
  [ssh_exists]="Chave SSH já existe, pulando"
  [ssh_pub]="Chave pública (cole em github.com/settings/keys):"
  [summary_title]="Versões instaladas"
  [final_title]="Falta só:"
  [final_1]="1. Fazer logout e login (ou reiniciar). Isso ativa o zsh como padrão e o grupo docker (docker sem sudo)."
  [final_2]="2. Abrir o terminal. Na primeira vez o Powerlevel10k abre o assistente (ou rode: p10k configure)."
  [final_3]="3. Se os ícones ficarem quebrados, use a fonte 'MesloLGS NF' no terminal."
  [final_4]="4. Testar o Docker:  docker run hello-world"
  [final_5]="5. Logar no GitHub:  gh auth login"
  [final_tip]="Dica: guarde o ~/.p10k.zsh junto com este script (repo de dotfiles) e copie de volta antes de abrir o terminal após uma reinstalação, para pular o assistente. Tokens e segredos vão em ~/.zshrc.local, nunca em um script."
  [L_user]="Usuário"
  [L_system]="Sistema"
  [L_ram]="RAM"
  [L_disk]="Disco"
  [L_uptime]="Uptime"
  [L_used_of]="usados de"
  [help]="Uso: bash setup-dev-ubuntu.sh [opções]\n\nOpções:\n  --lang <en-US|pt-BR>    Escolhe o idioma (pula o menu)\n  --components <lista>    Separados por vírgula: terminal,base,git,gh,python,node,docker,vscode\n                          (pula o menu de seleção)\n  -y, --yes               Não faz perguntas; usa padrões e variáveis de ambiente\n  -h, --help              Mostra esta ajuda\n\nVariáveis de ambiente:\n  SETUP_LANG, GIT_NAME, GIT_EMAIL\n  NODE_VERSION, DOCKER_VERSION, CODE_VERSION, GH_VERSION, PYTHON_VERSION, NVM_VERSION\n  INSTALL_<COMPONENTE>=true|false   (ex.: INSTALL_DOCKER=false)\n\nAs versões aceitam entrada parcial, ex.: NODE_VERSION=24 ou DOCKER_VERSION=27.3\n"
)

# t <key> [printf args...]  -> localized message (falls back to English)
t() {
  local key="$1"
  shift
  local fmt
  if [[ "$LANG_CODE" == "pt-BR" && -n "${MSG_PT[$key]+x}" ]]; then
    fmt="${MSG_PT[$key]}"
  else
    fmt="${MSG_EN[$key]:-$key}"
  fi
  # shellcheck disable=SC2059
  printf -- "$fmt" "$@"
}

# ===============================================================
# Helpers
# ===============================================================
log()  { echo -e "\n\033[1;36m==>\033[0m \033[1m$*\033[0m"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
L()    { log "$(t "$@")"; }
W()    { warn "$(t "$@")"; }
has()  { command -v "$1" >/dev/null 2>&1; }

cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; fi
  local f
  for f in "${TMP_FILES[@]:-}"; do
    if [[ -n "$f" ]]; then rm -f "$f"; fi
  done
}

# ask "prompt" "default" -> prints the answer (default if empty)
ask() {
  local prompt="$1" default="${2:-}" reply=""
  if [[ -n "$default" ]]; then prompt="$prompt [$default]"; fi
  read -r -p "$prompt: " reply </dev/tty || reply=""
  echo "${reply:-$default}"
}

# ask_yn "prompt" Y|N -> exit status 0 = yes
ask_yn() {
  local prompt="$1" def="${2:-Y}" reply="" hint
  if [[ "$def" == "Y" ]]; then hint="$(t hint_yn)"; else hint="$(t hint_ny)"; fi
  if [[ "$INTERACTIVE" != true || "$ASSUME_YES" == true ]]; then
    [[ "$def" == "Y" ]]
    return
  fi
  read -r -p "$prompt $hint " reply </dev/tty || reply=""
  reply="${reply:-$def}"
  case "${reply,,}" in
    y|yes|s|sim) return 0 ;;
    *) return 1 ;;
  esac
}

clone_if_missing() {
  local url="$1" dest="$2"
  if [[ -d "$dest" ]]; then
    echo "Already exists / Já existe: $dest"
  else
    git clone --depth 1 "$url" "$dest"
  fi
}

ensure_sudo() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then return 0; fi
  L sudo_prompt
  sudo -v
  (
    while true; do
      sudo -n true 2>/dev/null
      sleep 50
      kill -0 "$$" 2>/dev/null || exit 0
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
}

ensure_prereqs() {
  if [[ "$PREREQS_DONE" == true ]]; then return 0; fi
  ensure_sudo
  L prereqs
  sudo apt-get update -qq
  sudo apt-get install -y -qq curl ca-certificates gnupg software-properties-common
  PREREQS_DONE=true
}

# ===============================================================
# Arguments and language
# ===============================================================
valid_components() { local IFS=,; echo "${COMPONENTS[*]}"; }

apply_components_arg() {
  local item id found
  for id in "${COMPONENTS[@]}"; do SEL[$id]=false; done
  local IFS=','
  for item in $COMPONENTS_ARG; do
    item="${item// /}"
    if [[ -z "$item" ]]; then continue; fi
    found=false
    for id in "${COMPONENTS[@]}"; do
      if [[ "$id" == "${item,,}" ]]; then SEL[$id]=true; found=true; fi
    done
    if [[ "$found" != true ]]; then
      echo "$(t comp_unknown "$item" "$(valid_components)")" >&2
      exit 1
    fi
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)         SETUP_LANG="${2:-}"; shift 2 || shift ;;
      --lang=*)       SETUP_LANG="${1#*=}"; shift ;;
      --components)   COMPONENTS_ARG="${2:-}"; shift 2 || shift ;;
      --components=*) COMPONENTS_ARG="${1#*=}"; shift ;;
      -y|--yes)       ASSUME_YES=true; shift ;;
      -h|--help)      SHOW_HELP=true; shift ;;
      *) echo "Unknown option / Opção desconhecida: $1" >&2; exit 1 ;;
    esac
  done
}

normalize_lang() {
  case "${1,,}" in
    en|en-us|en_us|1) echo "en-US" ;;
    pt|pt-br|pt_br|2) echo "pt-BR" ;;
    *) echo "" ;;
  esac
}

detect_lang() {
  case "${LANG:-}" in
    pt_*|pt-*) echo "pt-BR" ;;
    *) echo "en-US" ;;
  esac
}

detect_interactive() {
  if ( : </dev/tty ) 2>/dev/null; then INTERACTIVE=true; fi
}

select_language() {
  local chosen="" default defnum reply

  if [[ -n "$SETUP_LANG" ]]; then
    chosen="$(normalize_lang "$SETUP_LANG")"
    if [[ -z "$chosen" ]]; then
      echo "Invalid language / Idioma inválido: $SETUP_LANG (use en-US or pt-BR)" >&2
      exit 1
    fi
  fi

  if [[ -z "$chosen" ]]; then
    default="$(detect_lang)"
    if [[ "$default" == "pt-BR" ]]; then defnum=2; else defnum=1; fi

    if [[ "$INTERACTIVE" == true && "$ASSUME_YES" != true ]]; then
      while [[ -z "$chosen" ]]; do
        echo
        echo "Select your language / Selecione o idioma:"
        echo "  1) English (en-US)"
        echo "  2) Português (pt-BR)"
        read -r -p "> [$defnum]: " reply </dev/tty || reply=""
        reply="${reply:-$defnum}"
        chosen="$(normalize_lang "$reply")"
      done
    else
      chosen="$default"
    fi
  fi

  LANG_CODE="$chosen"
}

preflight() {
  if [[ $EUID -eq 0 ]]; then
    echo "$(t no_root)" >&2
    exit 1
  fi
  if ! has apt-get; then
    echo "$(t no_apt)" >&2
    exit 1
  fi
  if [[ "$INTERACTIVE" != true ]]; then
    warn "$(t non_interactive)"
  fi
}

# ===============================================================
# Component selection menu
# ===============================================================
installed_info() {
  case "$1" in
    terminal) if [[ -d "$ZSH_DIR" ]]; then echo "Oh My Zsh"; fi ;;
    python)   if has python3; then python3 --version 2>/dev/null | awk '{print $2}'; fi ;;
    node)     if has node; then node -v 2>/dev/null; fi ;;
    docker)   if has docker; then docker --version 2>/dev/null | sed -E 's/Docker version ([^,]+),.*/\1/'; fi ;;
    vscode)   if has code; then code --version 2>/dev/null | head -n1; fi ;;
    gh)       if has gh; then gh --version 2>/dev/null | head -n1 | awk '{print $3}'; fi ;;
    *) : ;;
  esac
}

# Components that are skipped (not reinstalled) when already present
is_kept() {
  local v
  case "$1" in
    docker|vscode|gh) v="$(installed_info "$1" || true)"; [[ -n "$v" ]] ;;
    *) return 1 ;;
  esac
}

# render_menu [full|compact]  (full shows What/Why for each item)
render_menu() {
  local mode="${1:-full}" i=0 id mark tag name
  echo
  echo "$(t sel_title)"
  echo
  for id in "${COMPONENTS[@]}"; do
    i=$((i + 1))
    if [[ "${SEL[$id]}" == true ]]; then mark="[x]"; else mark="[ ]"; fi
    tag="$(installed_info "$id" || true)"
    name="$(t "c_${id}_name")"
    if [[ -n "$tag" ]]; then
      printf '  %s %d) %s  (%s)\n' "$mark" "$i" "$name" "$(t tag_installed "$tag")"
    else
      printf '  %s %d) %s\n' "$mark" "$i" "$name"
    fi
    if [[ "$mode" == full ]]; then
      printf '%s: %s\n' "$(t lbl_what)" "$(t "c_${id}_what")" | fold -s -w 72 | sed 's/^/        /'
      printf '%s: %s\n' "$(t lbl_why)" "$(t "c_${id}_why")"  | fold -s -w 72 | sed 's/^/        /'
      echo
    fi
  done
  if [[ "$mode" != full ]]; then echo; fi
}

menu_apply() {
  local tok="${1,,}" id
  case "$tok" in
    all)  for id in "${COMPONENTS[@]}"; do SEL[$id]=true; done ;;
    none) for id in "${COMPONENTS[@]}"; do SEL[$id]=false; done ;;
    ""|*[!0-9]*) W sel_invalid "$1" ;;
    *)
      if (( 10#$tok >= 1 && 10#$tok <= ${#COMPONENTS[@]} )); then
        id="${COMPONENTS[$((10#$tok - 1))]}"
        if [[ "${SEL[$id]}" == true ]]; then SEL[$id]=false; else SEL[$id]=true; fi
      else
        W sel_invalid "$1"
      fi
      ;;
  esac
}

select_components() {
  if [[ -n "$COMPONENTS_ARG" ]]; then return 0; fi
  if [[ "$INTERACTIVE" != true || "$ASSUME_YES" == true ]]; then return 0; fi
  local line tok mode=full
  while true; do
    render_menu "$mode"
    mode=compact
    echo "$(t sel_help)"
    read -r -p "> " line </dev/tty || line=""
    if [[ -z "${line// /}" ]]; then break; fi
    for tok in $line; do menu_apply "$tok"; done
  done
}

any_selected() {
  local id
  for id in "${COMPONENTS[@]}"; do
    if [[ "${SEL[$id]}" == true ]]; then return 0; fi
  done
  return 1
}

# ===============================================================
# Git identity
# ===============================================================
collect_git() {
  local cur_name cur_email
  cur_name="${GIT_NAME:-$(git config --global user.name 2>/dev/null || true)}"
  cur_email="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"

  if [[ "$INTERACTIVE" == true && "$ASSUME_YES" != true ]]; then
    echo
    echo "$(t git_intro)"
    GIT_NAME="$(ask "$(t git_name_prompt)" "$cur_name")"
    while true; do
      GIT_EMAIL="$(ask "$(t git_email_prompt)" "$cur_email")"
      if [[ -z "$GIT_EMAIL" || "$GIT_EMAIL" =~ $EMAIL_RE ]]; then break; fi
      W git_email_invalid
    done
  else
    GIT_NAME="$cur_name"
    GIT_EMAIL="$cur_email"
  fi

  # SSH key: only offered when there is an email and no key yet
  if [[ "$GENERATE_SSH_KEY" == true && -n "$GIT_EMAIL" ]]; then
    if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
      SSH_EXISTS=true
    elif ask_yn "$(t ssh_ask)" Y; then
      DO_SSH=true
    fi
  fi
}

# ===============================================================
# Version handlers
#   Each versioned component has three functions:
#     ver_prepare_<id>        make sure the version source is reachable
#     ver_list_<id>           print available versions (newest first)
#     ver_resolve_<id> SPEC   turn free-form input into an exact version
#                             (sets VEXACT[id] / VINFO[id]; returns 1 on no match)
# ===============================================================

# ---- apt-based (docker, vscode, gh) ----------------------------
apt_candidates() {
  apt-cache madison "$1" 2>/dev/null \
    | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 != "" && !seen[$2]++) print $2}'
}

# apt_resolve PKG SPEC -> prints the full apt version string
# SPEC can be: latest, "27", "27.3", "27.3.1", the full version, or "PKG 27.3"
apt_resolve() {
  local pkg="$1" spec="${2:-latest}" v bare re list
  spec="${spec#"$pkg"}"
  spec="${spec#[ =]}"
  spec="${spec#v}"
  list="$(apt_candidates "$pkg")"
  if [[ -z "$list" ]]; then return 1; fi

  case "${spec,,}" in
    ""|latest) head -n1 <<<"$list"; return 0 ;;
  esac

  while IFS= read -r v; do
    if [[ "$v" == "$spec" ]]; then echo "$v"; return 0; fi
  done <<<"$list"

  # Prefix match with a digit boundary: "27.3" matches 27.3.1 but not 27.30.1
  re="^$(printf '%s' "$spec" | sed 's/[].[\*^$+?(){}|\\]/\\&/g')([^0-9]|\$)"
  while IFS= read -r v; do
    bare="${v#*:}"   # drop the epoch (e.g. 5:27.3.1 -> 27.3.1)
    if [[ "$v" =~ $re || "$bare" =~ $re ]]; then echo "$v"; return 0; fi
  done <<<"$list"
  return 1
}

apt_list_versions() {
  local out
  out="$(apt_candidates "$1" | head -n 15)"
  if [[ -z "$out" ]]; then echo "  $(t ver_none)"; else sed 's/^/  /' <<<"$out"; fi
}

prepare_docker_repo() {
  if [[ -f /etc/apt/sources.list.d/docker.sources ]]; then return 0; fi
  ensure_prereqs
  L repo_prep "Docker"
  local codename
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  sudo apt-get update -qq
  REPO_ADDED=true
}

prepare_vscode_repo() {
  if [[ -f /etc/apt/sources.list.d/vscode.sources ]]; then return 0; fi
  ensure_prereqs
  L repo_prep "VS Code"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
  sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  # Stops the package from adding the same repository again (apt duplicate warning)
  echo "code code/add-microsoft-repo boolean false" | sudo debconf-set-selections
  sudo apt-get update -qq
  REPO_ADDED=true
}

prepare_gh_repo() {
  if [[ -f /etc/apt/sources.list.d/github-cli.list ]]; then return 0; fi
  ensure_prereqs
  L repo_prep "GitHub CLI"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  REPO_ADDED=true
}

ver_prepare_docker() { prepare_docker_repo; }
ver_list_docker()    { apt_list_versions docker-ce; }
ver_resolve_docker() { local v; v="$(apt_resolve docker-ce "$1")" || return 1; VEXACT[docker]="$v"; }

ver_prepare_vscode() { prepare_vscode_repo; }
ver_list_vscode()    { apt_list_versions code; }
ver_resolve_vscode() { local v; v="$(apt_resolve code "$1")" || return 1; VEXACT[vscode]="$v"; }

ver_prepare_gh()     { prepare_gh_repo; }
ver_list_gh()        { apt_list_versions gh; }
ver_resolve_gh()     { local v; v="$(apt_resolve gh "$1")" || return 1; VEXACT[gh]="$v"; }

# ---- Node.js (catalog from nodejs.org) --------------------------
# Builds a "version<TAB>lts-name-or-dash" list, newest first.
node_load_index() {
  if [[ -n "$NODE_CATALOG" && -s "$NODE_CATALOG" ]]; then return 0; fi
  local raw="${NODE_INDEX_FILE:-}"
  if [[ -z "$raw" || ! -s "$raw" ]]; then
    raw="$(mktemp)"
    TMP_FILES+=("$raw")
    if ! curl -fsSL --max-time 20 "$NODE_INDEX_URL" -o "$raw" 2>/dev/null; then return 1; fi
  fi
  NODE_CATALOG="$(mktemp)"
  TMP_FILES+=("$NODE_CATALOG")
  # one object per line (no nested objects in index.json), keep version + lts name
  tr '}' '\n' < "$raw" | sed -nE \
    -e 's/.*"version":"v([0-9]+\.[0-9]+\.[0-9]+)".*"lts":"([^"]+)".*/\1\t\2/p' \
    -e 't' \
    -e 's/.*"version":"v([0-9]+\.[0-9]+\.[0-9]+)".*/\1\t-/p' > "$NODE_CATALOG"
  [[ -s "$NODE_CATALOG" ]]
}

# node_resolve SPEC -> prints "version<TAB>lts-name"
# SPEC: lts | latest | krypton (codename) | lts/krypton | 24 | 24.20 | 24.20.0 | v24.20.0
node_resolve() {
  local spec="${1,,}" line="" name
  spec="${spec#v}"
  spec="${spec// /}"
  if [[ -z "$spec" ]]; then spec="lts"; fi
  case "$spec" in
    lts|lts/\*|--lts)
      line="$(awk -F'\t' '$2 != "-" {print; exit}' "$NODE_CATALOG")" ;;
    latest|current|node|stable)
      line="$(head -n1 "$NODE_CATALOG")" ;;
    lts/*)
      name="${spec#lts/}"
      line="$(awk -F'\t' -v n="$name" 'tolower($2) == n {print; exit}' "$NODE_CATALOG")" ;;
    [0-9]*)
      if [[ ! "$spec" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then return 1; fi
      # appending "." to both sides gives a clean boundary: "24.2" must not match 24.20.0
      line="$(awk -F'\t' -v s="$spec" 'index($1 ".", s ".") == 1 {print; exit}' "$NODE_CATALOG")" ;;
    [a-z]*)
      line="$(awk -F'\t' -v n="$spec" 'tolower($2) == n {print; exit}' "$NODE_CATALOG")" ;;
    *) return 1 ;;
  esac
  if [[ -z "$line" ]]; then return 1; fi
  printf '%s\n' "$line"
}

ver_prepare_node() {
  if ! node_load_index; then return 1; fi
}

ver_list_node() {
  if ! node_load_index; then echo "  $(t ver_none)"; return 0; fi
  head -n 20 "$NODE_CATALOG" | awk -F'\t' '{ if ($2 != "-") printf "  %s  (LTS %s)\n", $1, $2; else printf "  %s\n", $1 }'
}

ver_resolve_node() {
  local line
  if ! node_load_index; then
    # Offline: let nvm interpret the request itself
    W node_offline "$1"
    VEXACT[node]=""
    VINFO[node]=""
    return 0
  fi
  line="$(node_resolve "$1")" || return 1
  VEXACT[node]="${line%%$'\t'*}"
  VINFO[node]=""
  if [[ "${line#*$'\t'}" != "-" ]]; then VINFO[node]="LTS ${line#*$'\t'}"; fi
}

# What we hand to `nvm install`
node_target() {
  if [[ -n "${VEXACT[node]}" ]]; then
    echo "${VEXACT[node]}"
    return
  fi
  case "${VSPEC[node],,}" in
    ""|lts|lts/\*|--lts) echo "--lts" ;;
    latest|current|stable|node) echo "node" ;;
    *) echo "${VSPEC[node]#v}" ;;
  esac
}

# nvm: "latest" is read from the redirect of /releases/latest (no API rate limit)
resolve_nvm() {
  local url tag
  if [[ "${NVM_VERSION,,}" != "latest" ]]; then
    NVM_RESOLVED="v${NVM_VERSION#v}"
    return 0
  fi
  url="$(curl -fsSL --max-time 15 -o /dev/null -w '%{url_effective}' https://github.com/nvm-sh/nvm/releases/latest 2>/dev/null || true)"
  tag="${url##*/}"
  if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    NVM_RESOLVED="$tag"
  else
    NVM_RESOLVED="$NVM_FALLBACK"
    W nvm_fallback "$NVM_FALLBACK"
  fi
}

# ---- Python (apt names carry the version: python3.13) -----------
# "3.13", "python3.13", "313", "13" -> "3.13"
python_normalize() {
  local s="${1,,}"
  s="${s#python}"
  s="${s// /}"
  if   [[ "$s" =~ ^3\.([0-9]+)(\.[0-9]+)?$ ]]; then echo "3.${BASH_REMATCH[1]}"
  elif [[ "$s" =~ ^3([0-9]{1,2})$ ]];          then echo "3.${BASH_REMATCH[1]}"
  elif [[ "$s" =~ ^[0-9]{2}$ ]];               then echo "3.$s"
  else return 1
  fi
}

python_candidate() {
  apt-cache policy "python$1" 2>/dev/null | awk '/Candidate:/ {print $2}'
}

python_available() {
  local c
  c="$(python_candidate "$1")"
  [[ -n "$c" && "$c" != "(none)" ]]
}

ver_prepare_python() { :; }

ver_list_python() {
  apt-cache pkgnames python3. 2>/dev/null | grep -E '^python3\.[0-9]+$' | sort -V -r | sed 's/^python/  /' || true
  echo
  echo "  $(t python_list_note)"
}

ver_resolve_python() {
  local spec="${1,,}" minor
  case "$spec" in
    ""|system|default|latest)
      VEXACT[python]=""
      VINFO[python]="system"
      return 0 ;;
  esac
  minor="$(python_normalize "$spec")" || return 1
  if ! python_available "$minor"; then
    ensure_prereqs
    L python_ppa "$minor"
    sudo add-apt-repository -y ppa:deadsnakes/ppa >/dev/null 2>&1 || true
    sudo apt-get update -qq || true
    REPO_ADDED=true
    if ! python_available "$minor"; then
      W python_unavailable "$minor"
      return 1
    fi
  fi
  VEXACT[python]="$minor"
  VINFO[python]="$(python_candidate "$minor")"
}

# ---- generic driver ---------------------------------------------
# resolve_version ID SPEC -> 0 if resolved (and reports what it resolved to)
resolve_version() {
  local id="$1" spec="$2" low="${2,,}"
  VSPEC[$id]="$spec"
  VEXACT[$id]=""
  VINFO[$id]=""
  VPIN[$id]=false
  if ! "ver_resolve_$id" "$spec"; then return 1; fi
  case "$low" in
    ""|latest|system|default|lts|current) VPIN[$id]=false ;;
    *) VPIN[$id]=true ;;
  esac
  echo "  $(t ver_resolved "$spec" "${VEXACT[$id]:-${VSPEC[$id]}}${VINFO[$id]:+ (${VINFO[$id]})}")"
}

prompt_version() {
  local id="$1" spec def="${VSPEC[$1]}"
  "ver_prepare_$id" || true
  while true; do
    echo
    echo "$(t ver_hint "${VLABEL[$id]}" "$def" "$(t "ver_ex_$id")")"
    read -r -p "> " spec </dev/tty || spec=""
    spec="${spec:-$def}"
    case "${spec,,}" in
      list|ls|\?)
        echo "$(t ver_list_title)"
        "ver_list_$id"
        continue ;;
    esac
    if resolve_version "$id" "$spec"; then break; fi
    warn "$(t ver_no_match "$spec")"
    "ver_list_$id" | head -n 8
  done
}

resolve_all_versions() {
  local id spec pick=false any=false
  for id in "${VERSIONED[@]}"; do
    if [[ "${SEL[$id]}" == true ]] && ! is_kept "$id"; then any=true; fi
  done

  if [[ "$any" == true && "$INTERACTIVE" == true && "$ASSUME_YES" != true ]]; then
    echo
    if ask_yn "$(t ask_versions)" N; then pick=true; fi
  fi

  for id in "${VERSIONED[@]}"; do
    if [[ "${SEL[$id]}" != true ]]; then continue; fi
    if is_kept "$id"; then
      echo "$(t installed_keep "${VLABEL[$id]}" "$(installed_info "$id" || true)")"
      continue
    fi
    if [[ "$pick" == true ]]; then
      prompt_version "$id"
      continue
    fi
    spec="${VSPEC[$id]}"
    # Default requests need no lookup (except Node, which is cheap and shown in the plan)
    case "${spec,,}" in
      ""|latest|system) if [[ "$id" != node ]]; then continue; fi ;;
    esac
    "ver_prepare_$id" || true
    if ! resolve_version "$id" "$spec"; then
      echo "$(t ver_fail "${VLABEL[$id]}" "$spec")" >&2
      "ver_list_$id" | head -n 8 >&2
      exit 1
    fi
  done

  if [[ "${SEL[node]}" == true ]]; then resolve_nvm; fi
}

# ===============================================================
# Plan
# ===============================================================
plan_suffix() {
  local id="$1" exact
  case "$id" in
    node)
      exact="${VEXACT[node]:-${VSPEC[node]}}"
      echo " - Node ${exact}${VINFO[node]:+ (${VINFO[node]})}, nvm ${NVM_RESOLVED}" ;;
    python)
      if [[ -n "${VEXACT[python]}" ]]; then echo " - system + Python ${VEXACT[python]}"; else echo " - system"; fi ;;
    docker|vscode|gh)
      if is_kept "$id"; then
        echo " - $(t plan_kept)"
      elif [[ "${VPIN[$id]}" == true ]]; then
        echo " - ${VEXACT[$id]} ($(t plan_pinned))"
      else
        echo " - $(t plan_latest)"
      fi ;;
    git)
      echo " - ${GIT_NAME:-?} <${GIT_EMAIL:-?}>" ;;
    *) : ;;
  esac
}

show_plan() {
  local id
  echo
  echo "$(t plan_title)"
  for id in "${COMPONENTS[@]}"; do
    if [[ "${SEL[$id]}" == true ]]; then
      echo "  [x] $(t "c_${id}_name")$(plan_suffix "$id")"
    fi
  done
  echo
}

# ===============================================================
# Installers
# ===============================================================
hold_pinned() {
  local id="$1"
  shift
  if [[ "${VPIN[$id]}" == true ]]; then
    sudo apt-mark hold "$@" >/dev/null
    W pin_hold "$*" "$*"
  fi
}

install_base() {
  L base_update
  sudo apt-get update
  sudo apt-get install -y git curl wget unzip zip ca-certificates gnupg software-properties-common
}

install_base_dev() {
  L base_dev
  sudo apt-get install -y \
    build-essential pkg-config libssl-dev \
    jq ripgrep fd-find bat htop tree
}

install_fastfetch() {
  if has fastfetch; then
    L fastfetch_already
    return
  fi
  L fastfetch_install
  if sudo apt-get install -y fastfetch 2>/dev/null; then
    return
  fi
  echo "$(t fastfetch_fallback)"
  local deb_arch=""
  case "$(uname -m)" in
    x86_64)  deb_arch="amd64" ;;
    aarch64) deb_arch="aarch64" ;;
    *) W fastfetch_arch "$(uname -m)"; return ;;
  esac
  curl -fL -o /tmp/fastfetch.deb \
    "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${deb_arch}.deb"
  sudo apt-get install -y /tmp/fastfetch.deb
  rm -f /tmp/fastfetch.deb
}

install_ohmyzsh() {
  sudo apt-get install -y zsh fontconfig
  if [[ -d "$ZSH_DIR" ]]; then
    L omz_already
  else
    L omz_install
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  L plugins_clone
  mkdir -p "$ZSH_CUSTOM_DIR/plugins" "$ZSH_CUSTOM_DIR/themes"
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions     "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
  clone_if_missing https://github.com/marlonrichert/zsh-autocomplete    "$ZSH_CUSTOM_DIR/plugins/zsh-autocomplete"
  clone_if_missing https://github.com/romkatv/powerlevel10k             "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
}

install_font() {
  L font_install
  local font_dir="$HOME/.local/share/fonts"
  local base_url="https://github.com/romkatv/powerlevel10k-media/raw/master"
  mkdir -p "$font_dir"
  local style file
  for style in "Regular" "Bold" "Italic" "Bold Italic"; do
    file="MesloLGS NF ${style}.ttf"
    if [[ ! -f "$font_dir/$file" ]]; then
      curl -fL -o "$font_dir/$file" "${base_url}/MesloLGS%20NF%20${style// /%20}.ttf"
    fi
  done
  fc-cache -f

  # Best effort for GNOME Terminal; other terminals need manual configuration
  if has gsettings && gsettings list-schemas 2>/dev/null | grep -q "org.gnome.Terminal.ProfilesList"; then
    local profile_id p
    profile_id="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'" || true)"
    if [[ -n "$profile_id" ]]; then
      p="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/"
      gsettings set "$p" use-system-font false || true
      gsettings set "$p" font 'MesloLGS NF 12' || true
      echo "$(t font_gnome)"
    fi
  else
    W font_manual
  fi
}

install_python() {
  L python_install
  sudo apt-get install -y python3 python3-pip python3-venv python3-dev pipx
  # Ubuntu 24.04 blocks global `pip install` (PEP 668).
  # Use a venv per project, and pipx for command-line tools.
  local minor="${VEXACT[python]}"
  if [[ -n "$minor" ]]; then
    sudo apt-get install -y "python${minor}" "python${minor}-venv" "python${minor}-dev"
    echo "$(t python_extra "$minor" "$minor")"
  fi
}

install_node() {
  local target
  target="$(node_target)"
  L node_install "$NVM_RESOLVED" "$target"
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    if [[ "${SEL[terminal]}" == true ]]; then
      # our generated ~/.zshrc loads nvm, so keep the installer away from the profile files
      curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_RESOLVED}/install.sh" | PROFILE=/dev/null bash
    else
      curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_RESOLVED}/install.sh" | bash
    fi
  else
    echo "$(t nvm_already)"
  fi

  # nvm.sh does not play well with set -eu
  set +eu
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install "$target"
  nvm alias default "$(nvm current)"
  set -eu

  # pnpm/yarn via corepack
  corepack enable 2>/dev/null || W corepack_warn
}

install_docker() {
  if has docker; then
    L docker_already
  else
    L docker_install
    local pkg
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
      sudo apt-get remove -y "$pkg" >/dev/null 2>&1 || true
    done
    prepare_docker_repo
    sudo apt-get update -qq

    local engine=(docker-ce docker-ce-cli)
    if [[ "${VPIN[docker]}" == true ]]; then
      engine=("docker-ce=${VEXACT[docker]}" "docker-ce-cli=${VEXACT[docker]}")
    fi
    sudo apt-get install -y --allow-downgrades "${engine[@]}" containerd.io docker-buildx-plugin docker-compose-plugin
    hold_pinned docker docker-ce docker-ce-cli
  fi

  sudo systemctl enable --now docker 2>/dev/null || W docker_service_warn

  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    L docker_group "$USER"
  fi
}

install_vscode() {
  if has code; then
    L vscode_already
  else
    L vscode_install
    prepare_vscode_repo
    sudo apt-get update -qq
    if [[ "${VPIN[vscode]}" == true ]]; then
      sudo apt-get install -y --allow-downgrades "code=${VEXACT[vscode]}"
      hold_pinned vscode code
    else
      sudo apt-get install -y code
    fi
  fi

  if has code && [[ ${#VSCODE_EXTENSIONS[@]} -gt 0 ]]; then
    L vscode_ext
    local ext
    for ext in "${VSCODE_EXTENSIONS[@]}"; do
      if code --install-extension "$ext" --force >/dev/null 2>&1; then
        echo "$(t ext_ok "$ext")"
      else
        W ext_fail "$ext"
      fi
    done
  fi
}

install_gh() {
  if has gh; then
    L gh_already
    return
  fi
  L gh_install
  prepare_gh_repo
  sudo apt-get update -qq
  if [[ "${VPIN[gh]}" == true ]]; then
    sudo apt-get install -y --allow-downgrades "gh=${VEXACT[gh]}"
    hold_pinned gh gh
  else
    sudo apt-get install -y gh
  fi
}

configure_git() {
  L git_config
  git config --global init.defaultBranch main
  if [[ -n "$GIT_NAME" ]];  then git config --global user.name  "$GIT_NAME";  fi
  if [[ -n "$GIT_EMAIL" ]]; then git config --global user.email "$GIT_EMAIL"; fi
  if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
    W git_skip_warn
  fi
}

write_zshrc() {
  L zshrc_write
  if [[ -f "$HOME/.zshrc" ]]; then
    local backup
    backup="$HOME/.zshrc.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$HOME/.zshrc" "$backup"
    echo "$(t zshrc_backup "$backup")"
  fi

  # Plugin list follows what was actually selected (syntax-highlighting must stay last)
  local plugins="git sudo z"
  if [[ "${SEL[docker]}" == true ]]; then plugins="$plugins docker"; fi
  if [[ "${SEL[node]}" == true ]];   then plugins="$plugins npm nvm"; fi
  plugins="$plugins zsh-autosuggestions zsh-syntax-highlighting"

  cat > "$HOME/.zshrc" <<'ZSHRC_EOF'
# ===============================================================
# 1. Welcome message
#    MUST stay BEFORE the Powerlevel10k instant prompt, otherwise it
#    complains about "console output during initialization".
# ===============================================================
welcome() {
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
    return
  fi
  local ram_used ram_total disk
  ram_used=$(LC_ALL=C free -h | awk '/^Mem:/ {print $3}')
  ram_total=$(LC_ALL=C free -h | awk '/^Mem:/ {print $2}')
  disk=$(df -h / | awk 'NR==2 {print $3 " @@L_USED_OF@@ " $2 " (" $5 ")"}')
  printf '\n'
  printf '  👤 %-8s: %s\n' "@@L_USER@@" "$USER"
  printf '  💻 %-8s: %s\n' "@@L_SYSTEM@@" "$(. /etc/os-release && echo "$PRETTY_NAME")"
  printf '  🧠 %-8s: %s / %s\n' "@@L_RAM@@" "$ram_used" "$ram_total"
  printf '  💾 %-8s: %s\n' "@@L_DISK@@" "$disk"
  printf '  ⏱️  %-8s: %s\n' "@@L_UPTIME@@" "$(uptime -p | sed 's/up //')"
  printf '\n'
}
welcome

# ===============================================================
# 2. Powerlevel10k instant prompt
# ===============================================================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===============================================================
# 3. PATH and variables
# ===============================================================
export PATH="$HOME/.local/bin:$PATH"     # pipx and user binaries
export NVM_DIR="$HOME/.nvm"

# nvm loaded on demand (keeps terminal startup fast)
zstyle ':omz:plugins:nvm' lazy yes
zstyle ':omz:plugins:nvm' autoload yes   # auto-switch version with .nvmrc

# ===============================================================
# 4. Oh My Zsh
# ===============================================================
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# zsh-autocomplete: BEFORE oh-my-zsh.sh (and not in the plugins list)
source ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh

plugins=(@@PLUGINS@@)

source $ZSH/oh-my-zsh.sh

# ===============================================================
# 5. Aliases (Ubuntu names fd as fdfind and bat as batcat)
# ===============================================================
command -v fdfind >/dev/null 2>&1 && alias fd=fdfind
command -v batcat >/dev/null 2>&1 && alias bat=batcat

# ===============================================================
# 6. Powerlevel10k (generated by `p10k configure`)
# ===============================================================
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ===============================================================
# 7. Personal/secret stuff (tokens, private aliases).
#    Keep it OUT of the script and any public repo: use ~/.zshrc.local
# ===============================================================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
ZSHRC_EOF

  # Localize labels and fill in the plugin list
  sed -i \
    -e "s|@@PLUGINS@@|$plugins|g" \
    -e "s|@@L_USER@@|$(t L_user)|g" \
    -e "s|@@L_SYSTEM@@|$(t L_system)|g" \
    -e "s|@@L_RAM@@|$(t L_ram)|g" \
    -e "s|@@L_DISK@@|$(t L_disk)|g" \
    -e "s|@@L_UPTIME@@|$(t L_uptime)|g" \
    -e "s|@@L_USED_OF@@|$(t L_used_of)|g" \
    "$HOME/.zshrc"
}

set_default_shell() {
  L shell_set
  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "$SHELL" != "$zsh_path" ]]; then
    sudo chsh -s "$zsh_path" "$USER"
    echo "$(t shell_done "$zsh_path")"
  else
    echo "$(t shell_already)"
  fi
}

generate_ssh_key() {
  if [[ "$DO_SSH" == true ]]; then
    L ssh_generating
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519"
    echo
    echo "$(t ssh_pub)"
    cat "$HOME/.ssh/id_ed25519.pub"
  elif [[ "$SSH_EXISTS" == true ]]; then
    echo "$(t ssh_exists)"
  fi
}

summary() {
  echo
  echo "============== $(t summary_title) =============="
  printf "zsh     : %s\n" "$(zsh --version 2>/dev/null || echo '-')"
  printf "git     : %s\n" "$(git --version 2>/dev/null || echo '-')"
  printf "python3 : %s\n" "$(python3 --version 2>/dev/null || echo '-')"
  printf "node    : %s\n" "$(node -v 2>/dev/null || echo '-')"
  printf "npm     : %s\n" "$(npm -v 2>/dev/null || echo '-')"
  printf "docker  : %s\n" "$(docker --version 2>/dev/null || echo '-')"
  printf "compose : %s\n" "$(docker compose version 2>/dev/null || echo '-')"
  printf "code    : %s\n" "$(code --version 2>/dev/null | head -n1 || echo '-')"
  printf "gh      : %s\n" "$(gh --version 2>/dev/null | head -n1 || echo '-')"
  echo "================================================"
  echo
  echo "$(t final_title)"
  echo "  $(t final_1)"
  echo "  $(t final_2)"
  echo "  $(t final_3)"
  echo "  $(t final_4)"
  echo "  $(t final_5)"
  echo
  echo "$(t final_tip)"
}

# ===============================================================
# MAIN
# ===============================================================
main() {
  parse_args "$@"
  detect_interactive

  if [[ "$SHOW_HELP" == true ]]; then
    LANG_CODE="$(detect_lang)"
    if [[ -n "$SETUP_LANG" ]]; then
      LANG_CODE="$(normalize_lang "$SETUP_LANG")"
      if [[ -z "$LANG_CODE" ]]; then LANG_CODE="$(detect_lang)"; fi
    fi
    t help
    exit 0
  fi

  select_language
  trap cleanup EXIT
  preflight

  if [[ -n "$COMPONENTS_ARG" ]]; then apply_components_arg; fi

  echo
  echo "$(t intro_title)"
  echo "$(t intro_note)"

  select_components
  if ! any_selected; then
    echo "$(t sel_none)"
    exit 0
  fi

  if [[ "${SEL[git]}" == true ]]; then collect_git; fi
  resolve_all_versions

  show_plan
  if ! ask_yn "$(t ask_proceed)" Y; then
    echo "$(t aborted)"
    if [[ "$REPO_ADDED" == true ]]; then echo "$(t aborted_repos)"; fi
    exit 0
  fi

  ensure_sudo
  install_base
  if [[ "${SEL[base]}" == true ]]; then install_base_dev; fi

  if [[ "${SEL[terminal]}" == true ]]; then
    install_fastfetch
    install_ohmyzsh
    install_font
  fi

  if [[ "${SEL[python]}" == true ]]; then install_python; fi
  if [[ "${SEL[node]}"   == true ]]; then install_node;   fi
  if [[ "${SEL[docker]}" == true ]]; then install_docker; fi
  if [[ "${SEL[vscode]}" == true ]]; then install_vscode; fi
  if [[ "${SEL[gh]}"     == true ]]; then install_gh;     fi
  if [[ "${SEL[git]}"    == true ]]; then configure_git;  fi

  if [[ "${SEL[terminal]}" == true ]]; then
    write_zshrc
    set_default_shell
  fi

  if [[ "${SEL[git]}" == true ]]; then generate_ssh_key; fi
  summary
}

main "$@"
