# agenda_trabalho

Aplicativo Flutter para controle de jornada, intervalos, fotos, anotacoes, backup e exportacao em XLSX.

## Recursos

- Registro de entrada, saida e intervalos
- Calculo de horas trabalhadas, extras, saldo e adicional noturno
- Resumo por dia, mes e periodo personalizado
- Registro de fotos por dia
- Backup em JSON com fotos incorporadas
- Exportacao e compartilhamento de relatorio em XLSX
- QR Code para instalacao em outro aparelho
- Consulta de atualizacoes publicadas no GitHub
- Artigo do dia do CTB com cache local

## Estrutura

- `lib/pages/home_page.dart`: tela principal e composicao da interface
- `lib/models/`: modelos de dados do app
- `lib/services/`: persistencia, backup, atualizacao, CTB e exportacao
- `lib/utils/`: calculos de jornada e utilitarios de data
- `lib/widgets/`: componentes reutilizaveis

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
