# Setup DEV Ubuntu Tools

**English** · [Português (pt-BR)](#pt-br)

---

<a id="english"></a>

## English

A single script that sets up an Ubuntu machine for development. **You choose what to install** (each item is explained: what it is and why you might want it) and, if you want, **which version**. Versions accept partial input, so you can type `24`, `lts`, `27.3` or `3.13` instead of an exact package string. It asks everything up front, then runs unattended. It is safe to re-run: anything already installed is skipped.

### What you can install

| Component | What it is | Version choice |
|---|---|---|
| Shell experience | zsh, Oh My Zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-autocomplete`, Powerlevel10k, MesloLGS NF font, fastfetch welcome message | latest |
| Base tools | build-essential, pkg-config, libssl-dev, jq, ripgrep, fd, bat, htop, tree | distro |
| Git identity | commit name/email, `main` as default branch, optional ed25519 SSH key | n/a |
| GitHub CLI | `gh` from the official repository | yes |
| Python 3 | python3, pip, venv, dev headers, pipx; optionally a specific version side by side with the system one | yes |
| Node.js | nvm + Node.js, npm (ships with Node), corepack | yes |
| Docker | Docker Engine, Buildx and Compose from the official Docker repository | yes |
| VS Code | Visual Studio Code from the official Microsoft repository, plus extensions | yes |

### Requirements

- Ubuntu 24.04 (the target of this script) or an Ubuntu-based distro such as Linux Mint or Pop!_OS
- `sudo` access and an internet connection
- Run it as your **normal user**, not with `sudo` (the script calls `sudo` itself when needed)

Debian is not a target: the Docker step uses Docker's Ubuntu repository. On Debian, deselect Docker and install it from its official docs.

### Quick start

Download it, read it, then run it. It is a good habit to read any script that uses `sudo` before running it:

```bash
curl -fsSL -o setup-dev-ubuntu.sh \
  https://raw.githubusercontent.com/gustavo8000br/setup-dev-ubuntu-tools/main/setup-dev-ubuntu.sh

less setup-dev-ubuntu.sh      # read it first
bash setup-dev-ubuntu.sh
```

What happens:

1. You pick the language (English or Português).
2. You pick the components from an arrow-key checklist: ↑/↓ to move, Space to toggle, `a` for all, `n` for none, Enter to confirm. A panel under the list explains the highlighted item (what it is and why you might want it).
3. If you selected Git, it asks for your name and email, and whether to generate an SSH key.
4. It asks whether you want to pick specific versions. The default is the latest stable version of everything.
5. It shows the final plan with the exact versions and asks for confirmation.
6. It asks for your `sudo` password once and installs everything. Each step is one clean line with a spinner (`✔ Installing Docker Engine (12s)`); the noisy output of apt, git and curl goes to a log file instead of your screen.
7. At the end it prints the installed versions and the remaining manual steps.

### Choosing versions

When you answer yes to "pick specific versions", each selected tool shows a list: the recommended option first, a few recent versions, and **Other...**. Pick one with the arrows (or the number keys), or choose **Other...** to type a name or number:

| Tool | Accepted input | Example |
|---|---|---|
| Node.js | a major, minor or full version; `lts`; `latest`; an LTS codename | `24`, `24.20`, `24.20.0`, `lts`, `krypton`, `lts/jod` |
| Docker | any prefix of the package version, or `latest` | `27`, `27.3`, `27.3.1` |
| VS Code | any prefix of the version, or `latest` | `1.105` |
| GitHub CLI | any prefix of the version, or `latest` | `2.62` |
| Python | a minor version, or `system` | `3.13`, `python3.12`, `313`, `system` |

Typing `list` shows what is available. If nothing matches, it shows some available versions and asks again. Matching respects number boundaries: `27.3` matches `27.3.1`, but not `27.30.1`.

How each one is resolved:

- **Node.js:** the list comes from nodejs.org, so you see real versions and LTS names. If nodejs.org cannot be reached, your input is handed to nvm as is. nvm itself is installed from its latest release (`NVM_VERSION=latest`).
- **Docker, VS Code, GitHub CLI:** the script adds the official apt repository first, then matches your input against `apt-cache madison`. A **pinned** version gets an `apt-mark hold`, so a later `apt upgrade` will not change it. Undo it with `sudo apt-mark unhold <package>`.
- **Python:** the system `python3` is never replaced (Ubuntu tools depend on it). A specific version is installed **alongside** it as `python3.X`, with `-venv` and `-dev`. If it is not in the default repositories, the deadsnakes PPA is added automatically. Use it with `python3.13 -m venv .venv`.

Choosing versions needs `sudo` earlier (to read the package lists), and may add apt repositories before the final confirmation. If you abort after that, the script tells you where those repositories are.

### Options

```text
bash setup-dev-ubuntu.sh [--lang en-US|pt-BR] [--components a,b,c] [--yes] [--help]
```

| Option | What it does |
|---|---|
| `--lang en-US` / `--lang pt-BR` | Choose the language and skip the menu |
| `--components terminal,node,docker` | Choose components without the menu. Valid ids: `terminal,base,git,gh,python,node,docker,vscode` |
| `--plain` | Use simple numbered prompts instead of arrow-key menus (screen readers, limited terminals) |
| `-y`, `--yes` | Ask no questions; use defaults and environment variables |
| `-h`, `--help` | Show help |

Environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `SETUP_LANG` | asked | `en-US` or `pt-BR` |
| `GIT_NAME`, `GIT_EMAIL` | asked | Git identity |
| `NODE_VERSION` | `lts` | Node.js request (see the table above) |
| `DOCKER_VERSION` | `latest` | Docker Engine request |
| `CODE_VERSION` | `latest` | VS Code request |
| `GH_VERSION` | `latest` | GitHub CLI request |
| `PYTHON_VERSION` | `system` | `system` or a minor version such as `3.13` |
| `NVM_VERSION` | `latest` | nvm release, e.g. `v0.40.8` |
| `NO_COLOR` | unset | Set it to turn off colors |
| `INSTALL_<COMPONENT>` | `true` | Default selection, e.g. `INSTALL_DOCKER=false` |

Fully non-interactive example:

```bash
GIT_NAME="Jane Doe" GIT_EMAIL="jane@example.com" \
NODE_VERSION=24 DOCKER_VERSION=27.3 PYTHON_VERSION=3.13 \
  bash setup-dev-ubuntu.sh --lang en-US --components terminal,git,python,node,docker --yes
```

In non-interactive mode, a version that cannot be resolved stops the script with an error and a list of available versions, instead of silently installing something else. When there is no terminal at all (CI, for example), the script uses the defaults and the environment variables.

### Customizing

The VS Code extensions are a list at the top of the script (`VSCODE_EXTENSIONS`). Edit it to taste.

### What it changes on your system

- Installs packages with `apt` and adds the Docker, VS Code and GitHub CLI apt repositories (under `/etc/apt/sources.list.d/` and `/etc/apt/keyrings/`), plus the deadsnakes PPA if you ask for a Python version that Ubuntu does not ship
- Applies `apt-mark hold` to packages whose version you pinned
- **Overwrites `~/.zshrc`** (only if you selected the shell experience), after saving a backup as `~/.zshrc.bak.<date-time>`
- Creates `~/.oh-my-zsh`, `~/.nvm` and the MesloLGS NF fonts in `~/.local/share/fonts`
- Changes your default shell to zsh (`chsh`)
- Adds your user to the `docker` group
- Writes `~/.gitconfig` entries (and `~/.ssh/id_ed25519` if you accept the SSH key)
- Tries to set the font of the default GNOME Terminal profile to MesloLGS NF

### After it finishes

1. **Log out and back in** (or reboot). This activates zsh as the default shell and the `docker` group.
2. Open a terminal. On first launch, Powerlevel10k starts its configuration wizard (or run `p10k configure`).
3. If icons look broken, set your terminal font to **MesloLGS NF**.
4. Test Docker: `docker run hello-world`
5. Log in to GitHub: `gh auth login`

### Good to know

- **Clean screen, detailed log:** the full output of every command goes to `~/.local/state/setup-dev-ubuntu/install-<date-time>.log`. If a step fails, the script shows the last lines of that step and the path of the log.
- **Arrow-key menus need a real terminal** of at least 24 rows by 60 columns. Otherwise (or with `--plain`, or when the output is piped) the script falls back to numbered prompts on its own.
- **Secrets:** put tokens, API keys and private aliases in `~/.zshrc.local`. The generated `~/.zshrc` loads it if it exists, so you never need to put secrets in the script or in a public repo.
- **Fast shell startup:** nvm is loaded lazily through the Oh My Zsh `nvm` plugin. The first `node`/`npm` call in a session loads it.
- **Python on Ubuntu 24.04:** global `pip install` is blocked by design (PEP 668). Use `python3 -m venv` per project and `pipx` for command-line tools.
- **Docker group:** membership in the `docker` group is effectively root-equivalent on that machine. That is the standard trade-off for using Docker without `sudo`.
- **Already installed:** Docker, VS Code and GitHub CLI are kept as they are (no reinstall, no downgrade) and are not asked for a version.
- **Reinstalling later:** keep `~/.p10k.zsh` in a dotfiles repo and copy it back before opening the terminal to skip the Powerlevel10k wizard.

### Troubleshooting

| Problem | What to try |
|---|---|
| The menu looks garbled or the arrows do nothing | Run with `--plain` for numbered prompts, or enlarge the terminal window |
| zsh does not open by default | Log out and back in. Check with `echo $SHELL`. In VS Code, run "Terminal: Select Default Profile" |
| Broken icons in the prompt | Select the **MesloLGS NF** font in your terminal, then run `p10k configure` |
| `docker: permission denied` | Log out and back in so the `docker` group applies |
| "No version matches" | Type `list` to see what is available, or use a shorter prefix (`27` instead of `27.3.9`) |
| Python version not found | Try the minor version only (`3.13`). The deadsnakes PPA must support your Ubuntu release |
| A pinned package will not upgrade | That is the `apt-mark hold`. Run `sudo apt-mark unhold <package>` |
| A step failed | Read the last lines the script prints, or open the log file whose path is shown. It has the full output of every step |
| VS Code extension failed to install | Install it later from inside VS Code; the script continues either way |

### Contributing

Issues and pull requests are welcome. If you add a message to the script, add it to **both** languages (`MSG_EN` and `MSG_PT`).

### License

See the [LICENSE](LICENSE) file.

---

<a id="pt-br"></a>

## Português (pt-BR)

[English](#english) · **Português (pt-BR)**

Um único script que prepara uma máquina Ubuntu para desenvolvimento. **Você escolhe o que instalar** (cada item vem explicado: o que é e por que você pode querer) e, se quiser, **qual versão**. As versões aceitam entrada parcial, então dá pra digitar `24`, `lts`, `27.3` ou `3.13` em vez do nome exato do pacote. Ele pergunta tudo no começo e depois roda sozinho. Pode rodar de novo sem medo: o que já estiver instalado é pulado.

### O que você pode instalar

| Componente | O que é | Escolha de versão |
|---|---|---|
| Experiência de shell | zsh, Oh My Zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-autocomplete`, Powerlevel10k, fonte MesloLGS NF, boas-vindas com fastfetch | mais recente |
| Ferramentas base | build-essential, pkg-config, libssl-dev, jq, ripgrep, fd, bat, htop, tree | da distro |
| Identidade do Git | nome/e-mail dos commits, `main` como branch padrão, chave SSH ed25519 opcional | n/a |
| GitHub CLI | `gh` do repositório oficial | sim |
| Python 3 | python3, pip, venv, headers de dev, pipx; opcionalmente uma versão específica ao lado da do sistema | sim |
| Node.js | nvm + Node.js, npm (vem com o Node), corepack | sim |
| Docker | Docker Engine, Buildx e Compose do repositório oficial do Docker | sim |
| VS Code | Visual Studio Code do repositório oficial da Microsoft, mais extensões | sim |

### Requisitos

- Ubuntu 24.04 (alvo deste script) ou uma distro baseada em Ubuntu, como Linux Mint ou Pop!_OS
- Acesso ao `sudo` e conexão com a internet
- Rode como **usuário normal**, sem `sudo` na frente (o script chama o `sudo` sozinho quando precisa)

Debian não é alvo: a etapa do Docker usa o repositório do Docker para Ubuntu. No Debian, desmarque o Docker e instale pela documentação oficial.

### Início rápido

Baixe, leia e só depois rode. Ler qualquer script que usa `sudo` antes de executar é um bom hábito:

```bash
curl -fsSL -o setup-dev-ubuntu.sh \
  https://raw.githubusercontent.com/gustavo8000br/setup-dev-ubuntu-tools/main/setup-dev-ubuntu.sh

less setup-dev-ubuntu.sh      # leia antes
bash setup-dev-ubuntu.sh
```

O que acontece:

1. Você escolhe o idioma (English ou Português).
2. Você escolhe os componentes numa lista com setas: ↑/↓ para mover, Espaço para marcar/desmarcar, `a` para todos, `n` para nenhum, Enter para confirmar. Um painel abaixo da lista explica o item em foco (o que é e por que você pode querer).
3. Se selecionou o Git, ele pergunta seu nome e e-mail, e se deve gerar uma chave SSH.
4. Ele pergunta se você quer escolher versões específicas. O padrão é a versão estável mais recente de tudo.
5. Ele mostra o plano final com as versões exatas e pede confirmação.
6. Ele pede a senha do `sudo` uma vez e instala tudo. Cada etapa vira uma linha limpa com spinner (`✔ Instalando Docker Engine (12s)`); a saída barulhenta do apt, git e curl vai para um arquivo de log, não para a sua tela.
7. No final, mostra as versões instaladas e os passos manuais que faltam.

### Escolhendo versões

Se você responder sim para "escolher versões específicas", cada ferramenta selecionada mostra uma lista: a opção recomendada primeiro, algumas versões recentes e **Outra...**. Escolha com as setas (ou as teclas numéricas), ou escolha **Outra...** para digitar um nome ou número:

| Ferramenta | Entrada aceita | Exemplo |
|---|---|---|
| Node.js | versão maior, menor ou completa; `lts`; `latest`; codinome de LTS | `24`, `24.20`, `24.20.0`, `lts`, `krypton`, `lts/jod` |
| Docker | qualquer prefixo da versão do pacote, ou `latest` | `27`, `27.3`, `27.3.1` |
| VS Code | qualquer prefixo da versão, ou `latest` | `1.105` |
| GitHub CLI | qualquer prefixo da versão, ou `latest` | `2.62` |
| Python | uma versão menor, ou `system` | `3.13`, `python3.12`, `313`, `system` |

Digitar `list` mostra o que está disponível. Se nada combinar, ele mostra algumas versões disponíveis e pergunta de novo. A comparação respeita limites de número: `27.3` casa com `27.3.1`, mas não com `27.30.1`.

Como cada uma é resolvida:

- **Node.js:** a lista vem do nodejs.org, então você vê versões e nomes de LTS reais. Se o nodejs.org não estiver acessível, sua entrada é repassada ao nvm do jeito que veio. O próprio nvm é instalado na última release (`NVM_VERSION=latest`).
- **Docker, VS Code, GitHub CLI:** o script adiciona o repositório apt oficial primeiro e depois compara sua entrada com o `apt-cache madison`. Uma versão **fixada** recebe `apt-mark hold`, então um `apt upgrade` futuro não a altera. Para desfazer: `sudo apt-mark unhold <pacote>`.
- **Python:** o `python3` do sistema nunca é substituído (ferramentas do Ubuntu dependem dele). Uma versão específica é instalada **ao lado**, como `python3.X`, com `-venv` e `-dev`. Se ela não estiver nos repositórios padrão, o PPA deadsnakes é adicionado automaticamente. Use com `python3.13 -m venv .venv`.

Escolher versões exige `sudo` mais cedo (para ler as listas de pacotes) e pode adicionar repositórios apt antes da confirmação final. Se você cancelar depois disso, o script avisa onde esses repositórios estão.

### Opções

```text
bash setup-dev-ubuntu.sh [--lang en-US|pt-BR] [--components a,b,c] [--yes] [--help]
```

| Opção | O que faz |
|---|---|
| `--lang en-US` / `--lang pt-BR` | Escolhe o idioma e pula o menu |
| `--components terminal,node,docker` | Escolhe componentes sem o menu. Ids válidos: `terminal,base,git,gh,python,node,docker,vscode` |
| `--plain` | Usa perguntas numeradas simples em vez de menus com setas (leitores de tela, terminais limitados) |
| `-y`, `--yes` | Não faz perguntas; usa padrões e variáveis de ambiente |
| `-h`, `--help` | Mostra a ajuda |

Variáveis de ambiente:

| Variável | Padrão | Para quê |
|---|---|---|
| `SETUP_LANG` | perguntado | `en-US` ou `pt-BR` |
| `GIT_NAME`, `GIT_EMAIL` | perguntado | Identidade do Git |
| `NODE_VERSION` | `lts` | Pedido de versão do Node.js (veja a tabela acima) |
| `DOCKER_VERSION` | `latest` | Pedido de versão do Docker Engine |
| `CODE_VERSION` | `latest` | Pedido de versão do VS Code |
| `GH_VERSION` | `latest` | Pedido de versão do GitHub CLI |
| `PYTHON_VERSION` | `system` | `system` ou uma versão menor como `3.13` |
| `NVM_VERSION` | `latest` | Release do nvm, ex.: `v0.40.8` |
| `NO_COLOR` | não definida | Defina para desligar as cores |
| `INSTALL_<COMPONENTE>` | `true` | Seleção padrão, ex.: `INSTALL_DOCKER=false` |

Exemplo totalmente sem interação:

```bash
GIT_NAME="Fulano de Tal" GIT_EMAIL="fulano@exemplo.com" \
NODE_VERSION=24 DOCKER_VERSION=27.3 PYTHON_VERSION=3.13 \
  bash setup-dev-ubuntu.sh --lang pt-BR --components terminal,git,python,node,docker --yes
```

No modo sem interação, uma versão que não puder ser resolvida interrompe o script com erro e uma lista de versões disponíveis, em vez de instalar outra coisa em silêncio. Quando não há terminal nenhum (CI, por exemplo), o script usa os padrões e as variáveis de ambiente.

### Personalizando

As extensões do VS Code ficam numa lista no topo do script (`VSCODE_EXTENSIONS`). Edite ao seu gosto.

### O que ele altera no seu sistema

- Instala pacotes com `apt` e adiciona os repositórios apt do Docker, VS Code e GitHub CLI (em `/etc/apt/sources.list.d/` e `/etc/apt/keyrings/`), além do PPA deadsnakes se você pedir uma versão de Python que o Ubuntu não traz
- Aplica `apt-mark hold` nos pacotes cuja versão você fixou
- **Sobrescreve o `~/.zshrc`** (só se você selecionou a experiência de shell), depois de salvar um backup como `~/.zshrc.bak.<data-hora>`
- Cria `~/.oh-my-zsh`, `~/.nvm` e as fontes MesloLGS NF em `~/.local/share/fonts`
- Troca seu shell padrão para o zsh (`chsh`)
- Adiciona seu usuário ao grupo `docker`
- Grava entradas no `~/.gitconfig` (e `~/.ssh/id_ed25519` se você aceitar a chave SSH)
- Tenta definir a fonte MesloLGS NF no perfil padrão do GNOME Terminal

### Depois que terminar

1. **Faça logout e login** (ou reinicie). Isso ativa o zsh como shell padrão e o grupo `docker`.
2. Abra o terminal. Na primeira vez, o Powerlevel10k abre o assistente de configuração (ou rode `p10k configure`).
3. Se os ícones ficarem quebrados, use a fonte **MesloLGS NF** no terminal.
4. Teste o Docker: `docker run hello-world`
5. Faça login no GitHub: `gh auth login`

### Bom saber

- **Tela limpa, log detalhado:** a saída completa de cada comando vai para `~/.local/state/setup-dev-ubuntu/install-<data-hora>.log`. Se uma etapa falhar, o script mostra as últimas linhas daquela etapa e o caminho do log.
- **Menus com setas precisam de um terminal de verdade** com pelo menos 24 linhas por 60 colunas. Caso contrário (ou com `--plain`, ou quando a saída é redirecionada), o script volta sozinho para perguntas numeradas.
- **Segredos:** coloque tokens, chaves de API e aliases privados em `~/.zshrc.local`. O `~/.zshrc` gerado carrega esse arquivo se ele existir, então você nunca precisa pôr segredo no script nem em repositório público.
- **Terminal rápido:** o nvm é carregado sob demanda pelo plugin `nvm` do Oh My Zsh. A primeira chamada de `node`/`npm` na sessão carrega o nvm.
- **Python no Ubuntu 24.04:** o `pip install` global é bloqueado de propósito (PEP 668). Use `python3 -m venv` por projeto e `pipx` para ferramentas de linha de comando.
- **Grupo docker:** estar no grupo `docker` equivale, na prática, a ter root naquela máquina. É o custo padrão de usar Docker sem `sudo`.
- **Já instalados:** Docker, VS Code e GitHub CLI são mantidos como estão (sem reinstalar, sem downgrade) e não perguntam versão.
- **Reinstalando depois:** guarde o `~/.p10k.zsh` num repositório de dotfiles e copie de volta antes de abrir o terminal para pular o assistente do Powerlevel10k.

### Solução de problemas

| Problema | O que tentar |
|---|---|
| O menu fica bagunçado ou as setas não fazem nada | Rode com `--plain` para perguntas numeradas, ou aumente a janela do terminal |
| O zsh não abre por padrão | Faça logout e login. Confira com `echo $SHELL`. No VS Code, use "Terminal: Select Default Profile" |
| Ícones quebrados no prompt | Selecione a fonte **MesloLGS NF** no terminal e rode `p10k configure` |
| `docker: permission denied` | Faça logout e login para o grupo `docker` valer |
| "Nenhuma versão combina" | Digite `list` para ver as disponíveis, ou use um prefixo menor (`27` em vez de `27.3.9`) |
| Versão do Python não encontrada | Tente só a versão menor (`3.13`). O PPA deadsnakes precisa suportar sua versão do Ubuntu |
| Um pacote fixado não atualiza | É o `apt-mark hold`. Rode `sudo apt-mark unhold <pacote>` |
| Uma etapa falhou | Leia as últimas linhas que o script mostra, ou abra o log cujo caminho aparece na tela. Ele tem a saída completa de cada etapa |
| Extensão do VS Code falhou | Instale depois pelo próprio VS Code; o script continua de qualquer jeito |

### Contribuindo

Issues e pull requests são bem-vindos. Se você adicionar uma mensagem ao script, adicione nos **dois** idiomas (`MSG_EN` e `MSG_PT`).

### Licença

Veja o arquivo [LICENSE](LICENSE).
