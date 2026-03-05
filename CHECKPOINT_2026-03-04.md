# CHECKPOINT — RDrive

Data: 2026-03-04
Status: ativo
Escopo: instalador via Release/Tarball + GUI Yad (preparação para l18n)

## Resumo do estado atual

- **Arquitetura refatorada (Tarball/Linux Standard)**: O modelo de instalação foi alterado de um "script monolítico" para uma estrutura padrão `src/` e `assets/`. O script instalador (`install.sh`) copia apenas os binários para `~/.local/bin/rdrive` e `~/.local/bin/rdrive-gui`.
- **GUI migrada de Zenity para Yad**: A interface gráfica foi totalmente portada para `yad`. Os bugs relacionados à delimitação de listas (pipes `|`) e tamanho de janelas foram devidamente tratados (ex. flag explícita `YAD_OPTS` e delimitador de coluna `--separator=""`).
- **Instalador sem elevação sistemática**: O novo `install.sh` analisa com `command -v` se as dependências (rclone, fuse3, yad, jq) já existem. Apenas requisitará a senha sudo pela GUI caso algum desses pacotes de sistema esteja efetivamente ausente.
- **CLI/Gerador**: O motor central continua operando sob o comando `rdrive` (antigo `rdrive-install.sh`). Ele é o responsável por ler o `~/.config/rdrive/rdrive.conf`, gerar os perfis do `rclone`, injetar o autostart (`XDG`) e gerar os shell-scripts em `~/.local/lib/rdrive`.
- As resoluções de caminho e FUSE (`--allow-other`) permanecem funcionais, como estruturado na arquitetura anterior.

## Comportamento atual

- Menu de configurações e operações do GUI continuam como o esperado, sendo orquestrados pelo motor yad.
- Os parâmetros do instalador foram polidos:
  - `$ ./install.sh` ou `$ ./install.sh --install` (Instala componentes e desktop menu)
  - `$ ./install.sh --uninstall` (Limpa atalhos `.svg` / `.desktop` do XDG e os binários em `~/.local/bin`)
- Qualquer problema com variáveis globais não definidas (ex. `GUI_ICON`) no `set -e -u` do bash estrito já foi saneado.

## Arquivos principais

- `install.sh` (O distribuidor XDG / Instalador Oficial do pacote Tarball)
- `src/rdrive.sh` (O antigo `rdrive-install.sh`, atua sob a invocação CLI `rdrive` para setup dos helpers / config logic)
- `src/rdrive-gui.sh` (O front-end wizard portado para `yad`, no bash invocado como `rdrive-gui`)
- `assets/rdrive-gui-icon.svg` e `assets/rdrive.desktop` (Ativos estáticos para menus de aplicativo)
- `README-pt.md`
- `README-en.md`
- `README.md`
- `LICENSE.md`

## Pendências (Próximos Passos)

- **Prioridade 1: L18N (Internacionalização)**. A documentação está pronta e os bugs de arquitetura resolvidos. Será necessário extrair as "strings" fixas do `src/rdrive-gui.sh` para arquivos no formato `locales/pt_BR.sh` e `locales/en_US.sh`, carregando-as dinamicamente através da variável baseada de `$LANG` (ou similar).
