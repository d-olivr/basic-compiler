%{
#include <iostream>
#include <string>
#include <stdio.h>
#include <map>
#include <stack>
#include <vector>
#include <cstdlib>

#define YYSTYPE atributos
using namespace std;

int yylex();

// --- ESTRUTURA DE ATRIBUTOS (precisa vir antes dos prototypes que a usam) ---
struct atributos {
    string label;
    string traducao;
    string tipo;
    vector<string> listaLabels;  // usado em listas de argumentos de chamada de funcao
    vector<string> listaTipos;   // usado em listas de argumentos de chamada de funcao
};

// --- PROTÓTIPOS DAS FUNÇÕES ---
string gentempcode();
string genlabel();
string gerarCast(string label_origem, string tipo_origem, string tipo_destino, string &traducao_acumulada);
string tirarCastSeNecessario(string tipoDestino, string tipoOrigem, string labelOrigem, string &traducao);
string gerarAtribuicaoComposta(string varNome, string op, atributos e);
string gerarAtribuicaoCompostaArray(string varNome, atributos idx, string op, atributos e);
string gerarAtribuicaoCompostaMatriz(string varNome, atributos idxLinha, atributos idxColuna, string op, atributos e);
string gerarOperacaoAritmetica(string op, atributos e1, atributos e3, atributos &res);
string gerarOperacaoRelacional(string op, atributos e1, atributos e3, atributos &res);
string gerarOperacaoLogica(string op, atributos e1, atributos e3, atributos &res);
string gerarOperacaoMod(atributos e1, atributos e3, atributos &res);
string gerarOperacaoPotencia(atributos e1, atributos e3, atributos &res);
void iniciarDeclaracaoFuncao(string nome, string tipoRetorno, vector<string> tiposParam, vector<string> nomesParam, atributos &dadosPendentes);
void finalizarDeclaracaoFuncao(atributos dadosPendentes, string corpoTraducao);

struct Variavel {
    string tipo;
    string label;
    int is_array;
    string col_size;
};

struct Funcao {
    string tipoRetorno;
    vector<string> tiposParam;
    vector<string> nomesParam;
    string labelC; // nome usado no C gerado (igual ao nome FOCA, prefixado para evitar colisao)
};

struct DadosForeach {
    string idxLabel;
    string itemLabel;
    string arrLabel;
    string Lcond;
    string Lstep;
    string Lend;
    string Ltrue;
    string tamTrad;
    string tamLabel;
};

// --- VARIÁVEIS GLOBAIS ---
int var_temp_qnt = 0;
int label_qnt = 0; 
string codigo_gerado;
string funcoes_geradas = ""; // código C de todas as funções (fora do main)
vector<string> pilhaVarsTemporarias; // buffer de declarações de variáveis/temporários por função em construção
stack<string> stack_break;
stack<string> stack_continue;
stack<string> stack_switch_expr;
stack<string> stack_switch_flag;
stack<map<string, Variavel>> pilhaEscopos;
map<string, Funcao> tabelaFuncoes;
stack<string> pilhaTipoRetornoAtual; // tipo de retorno da função sendo parseada (para checar 'return')
stack<DadosForeach> stack_foreach; // dados pendentes de foreach entre a mid-rule action e a acao final
extern int linha;
bool houveErro = false; // setada por erro lexico, sintatico ou semantico; impede geracao de codigo no final

#define vars_temporarias pilhaVarsTemporarias.back()

// --- FUNÇÕES DE APOIO ---
void entrarEscopo() { pilhaEscopos.push(map<string, Variavel>()); }
void sairEscopo() { pilhaEscopos.pop(); }
void declararVariavel(string nome, string tipo, string label) { pilhaEscopos.top()[nome] = {tipo, label, 0, ""}; }
void declararVariavelArray(string nome, string tipo, string label, int dim, string c_size = "") { pilhaEscopos.top()[nome] = {tipo, label, dim, c_size}; }

Variavel buscarVariavel(string nome) {
    stack<map<string, Variavel>> temp = pilhaEscopos;
    while (!temp.empty()) {
        if (temp.top().find(nome) != temp.top().end()) return temp.top()[nome];
        temp.pop();
    }
    return {"", "", 0, ""};
}

void yyerror(string msg) {
    houveErro = true;
    string texto = "Erro Sintatico na linha " + to_string(linha) + ": " + msg;
    cout << texto << endl;
    cerr << texto << endl;
    exit(1);
}
void erroSemantico(string msg) {
    houveErro = true;
    string texto = "Erro Semantico na linha " + to_string(linha) + ": " + msg;
    cout << texto << endl;
    cerr << texto << endl;
    exit(1);
}
%}

%token TK_NUM TK_ID TK_TIPO_INT TK_TIPO_FLOAT TK_TIPO_BOOL TK_TIPO_CHAR TK_TIPO_STRING
%token TK_TRUE TK_FALSE TK_ATRIB TK_E TK_OU TK_NAO TK_IGUAL TK_DIFERENTE
%token TK_MENOR_IGUAL TK_MAIOR_IGUAL TK_PRINT TK_READ
%token TK_IF TK_ELSE TK_WHILE TK_FOR TK_DO TK_FOREACH
%token TK_BREAK TK_CONTINUE
%token TK_SWITCH TK_CASE TK_DEFAULT
%token TK_MAIS_IGUAL TK_MENOS_IGUAL TK_VEZES_IGUAL TK_DIV_IGUAL
%token TK_INC TK_DEC
%token TK_POW TK_MOD
%token TK_RETURN TK_VOID
%token TK_VAR

%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/' TK_MOD
%right TK_POW
%right TK_NAO
%right UMENOS UMAIS
%left TK_INC TK_DEC

%%

programa : { pilhaVarsTemporarias.push_back(""); } entrar_escopo lista_comandos {
    string corpoMain = "#include <stdio.h>\n#include <stdlib.h>\n#include <stdbool.h>\n\n" + funcoes_geradas + "int main() {\n" + pilhaVarsTemporarias.back() + "\n" + $3.traducao + "\treturn 0;\n}\n";
    codigo_gerado = corpoMain;
};

lista_comandos : lista_comandos comando { $$.traducao = $1.traducao + $2.traducao; }
               | comando { $$.traducao = $1.traducao; };

entrar_escopo : { entrarEscopo(); };
sair_escopo   : { sairEscopo(); };

comando : declaracao ';' { $$.traducao = $1.traducao; }
        | subprograma_tipado { $$.traducao = ""; }
        | subprograma_void { $$.traducao = ""; }
        | atribuicao ';' { $$.traducao = $1.traducao; }
        | condicional    { $$.traducao = $1.traducao; }
        | iterativo      { $$.traducao = $1.traducao; }
        | TK_PRINT '(' E ')' ';'
        {
            string formato;
            string label = $3.label;
            string trad = $3.traducao;
            if ($3.tipo == "float") {
                formato = "\"%f\\n\"";
            } else if ($3.tipo == "int") {
                formato = "\"%d\\n\"";
            } else if ($3.tipo == "bool") {
                formato = "\"%d\\n\"";
            } else {
                erroSemantico("Tipo '" + $3.tipo + "' nao suportado pelo comando 'print'.");
            }
            $$.traducao = trad + "\tprintf(" + formato + ", " + label + ");\n";
        }
        | TK_READ '(' TK_ID ')' ';'
        {
            Variavel v = buscarVariavel($3.label);
            if (v.tipo == "") erroSemantico("Variavel '" + $3.label + "' nao declarada.");
            if (v.is_array != 0) erroSemantico("Nao e possivel usar 'read' diretamente em um array; leia para uma variavel escalar e atribua a posicao desejada.");
            string formato;
            if (v.tipo == "float") formato = "\"%f\"";
            else if (v.tipo == "int") formato = "\"%d\"";
            else erroSemantico("Tipo '" + v.tipo + "' nao suportado pelo comando 'read'.");
            $$.traducao = "\tscanf(" + formato + ", &" + v.label + ");\n";
        }
        | '{' entrar_escopo lista_comandos '}' sair_escopo { $$.traducao = $3.traducao; }
        | TK_BREAK ';'
        {
            if (stack_break.empty()) erroSemantico("Comando 'break' fora de um laco de repeticao ou switch.");
            $$.traducao = "\tgoto " + stack_break.top() + ";\n";
        }
        | TK_BREAK TK_NUM ';'
        {
            if (stack_break.empty()) erroSemantico("Comando 'break' fora de um laco de repeticao ou switch.");
            int niveis = atoi($2.label.c_str());
            if (niveis <= 0) erroSemantico("O nivel do break deve ser um numero maior que zero.");
            if (niveis > stack_break.size()) erroSemantico("Nivel de 'break' invalido. Solicitado " + to_string(niveis) + " mas possui " + to_string(stack_break.size()) + " escopos.");
            stack<string> pilha_aux;
            for (int i = 1; i < niveis; i++) {
                pilha_aux.push(stack_break.top());
                stack_break.pop();
            }
            string label_alvo = stack_break.top();
            while (!pilha_aux.empty()) {
                stack_break.push(pilha_aux.top());
                pilha_aux.pop();
            }
            $$.traducao = "\tgoto " + label_alvo + ";\n";
        }
        | TK_CONTINUE ';'
        {
            if (stack_continue.empty()) erroSemantico("Comando 'continue' fora de um laco de repeticao.");
            $$.traducao = "\tgoto " + stack_continue.top() + ";\n";
        }
        | estrutura_switch { $$.traducao = $1.traducao; }
        | TK_RETURN E ';'
        {
            if (pilhaTipoRetornoAtual.empty()) erroSemantico("Comando 'return' usado fora de uma funcao.");
            string tipoEsperado = pilhaTipoRetornoAtual.top();
            if (tipoEsperado == "void") erroSemantico("Funcao do tipo 'void' nao pode retornar um valor.");
            string trad = $2.traducao;
            string labelFinal = tirarCastSeNecessario(tipoEsperado, $2.tipo, $2.label, trad);
            $$.traducao = trad + "\treturn " + labelFinal + ";\n";
        }
        | TK_RETURN ';'
        {
            if (pilhaTipoRetornoAtual.empty()) erroSemantico("Comando 'return' usado fora de uma funcao.");
            if (pilhaTipoRetornoAtual.top() != "void") erroSemantico("Funcao com retorno deve usar 'return <expressao>;'.");
            $$.traducao = "\treturn;\n";
        }
        | TK_ID '(' lista_args_opcional ')' ';'
        {
            if (tabelaFuncoes.find($1.label) == tabelaFuncoes.end()) erroSemantico("Funcao '" + $1.label + "' nao declarada.");
            Funcao f = tabelaFuncoes[$1.label];
            if (f.tiposParam.size() != $3.listaTipos.size()) erroSemantico("Numero incorreto de argumentos na chamada de '" + $1.label + "'.");
            string trad = $3.traducao;
            string argsC = "";
            for (size_t i = 0; i < f.tiposParam.size(); i++) {
                string labelArg = tirarCastSeNecessario(f.tiposParam[i], $3.listaTipos[i], $3.listaLabels[i], trad);
                argsC += (i > 0 ? ", " : "") + labelArg;
            }
            $$.traducao = trad + "\t" + f.labelC + "(" + argsC + ");\n";
        }
        ;

tipo : TK_TIPO_INT   { $$.tipo = "int"; }
     | TK_TIPO_FLOAT { $$.tipo = "float"; }
     | TK_TIPO_BOOL  { $$.tipo = "bool"; }
     ;

// ---------------- SUBPROGRAMAS (FUNÇÕES) ----------------
// Funcoes com tipo de retorno void usam um prefixo exclusivo (TK_VOID), sem conflito com declaracao.
// Funcoes com retorno int/float/bool sao tratadas dentro de declaracao_ou_subprograma,
// pois compartilham o mesmo prefixo "tipo TK_ID" das declaracoes de variavel/array.

subprograma_void : TK_VOID TK_ID '(' lista_params_decl ')'
{
    iniciarDeclaracaoFuncao($2.label, "void", $4.listaTipos, $4.listaLabels, $$);
}
'{' lista_comandos '}'
{
    finalizarDeclaracaoFuncao($6, $8.traducao);
    $$.traducao = "";
}
;

subprograma_tipado : tipo TK_ID '(' lista_params_decl ')'
{
    iniciarDeclaracaoFuncao($2.label, $1.tipo, $4.listaTipos, $4.listaLabels, $$);
}
'{' lista_comandos '}'
{
    finalizarDeclaracaoFuncao($6, $8.traducao);
    $$.traducao = "";
}
;

lista_params_decl : /* vazio */ { /* listas ja iniciam vazias por default */ }
                   | lista_params_decl_nao_vazia { $$.listaTipos = $1.listaTipos; $$.listaLabels = $1.listaLabels; }
                   ;

lista_params_decl_nao_vazia : tipo TK_ID
                             {
                                 $$.listaTipos.push_back($1.tipo);
                                 $$.listaLabels.push_back($2.label);
                             }
                             | lista_params_decl_nao_vazia ',' tipo TK_ID
                             {
                                 $$.listaTipos = $1.listaTipos;
                                 $$.listaLabels = $1.listaLabels;
                                 $$.listaTipos.push_back($3.tipo);
                                 $$.listaLabels.push_back($4.label);
                             }
                             ;

lista_args_opcional : /* vazio */ { $$.traducao = ""; }
                     | lista_args { $$.traducao = $1.traducao; $$.listaTipos = $1.listaTipos; $$.listaLabels = $1.listaLabels; }
                     ;

lista_args : E
           {
               $$.traducao = $1.traducao;
               $$.listaTipos.push_back($1.tipo);
               $$.listaLabels.push_back($1.label);
           }
           | lista_args ',' E
           {
               $$.traducao = $1.traducao + $3.traducao;
               $$.listaTipos = $1.listaTipos;
               $$.listaLabels = $1.listaLabels;
               $$.listaTipos.push_back($3.tipo);
               $$.listaLabels.push_back($3.label);
           }
           ;

declaracao : tipo TK_ID
{
    Variavel v = buscarVariavel($2.label);
    if (v.tipo != "" && pilhaEscopos.top().find($2.label) != pilhaEscopos.top().end()) {
        erroSemantico("Variavel '" + $2.label + "' ja declarada neste escopo.");
    }
    string realLabel = $2.label + "_" + to_string(linha);
    declararVariavel($2.label, $1.tipo, realLabel);
    vars_temporarias += "\t" + $1.tipo + " " + realLabel + ";\n";
    $$.traducao = "";
}
| tipo TK_ID TK_ATRIB E
{
    Variavel v = buscarVariavel($2.label);
    if (v.tipo != "" && pilhaEscopos.top().find($2.label) != pilhaEscopos.top().end()) {
        erroSemantico("Variavel '" + $2.label + "' ja declarada neste escopo.");
    }
    string realLabel = $2.label + "_" + to_string(linha);
    declararVariavel($2.label, $1.tipo, realLabel);
    vars_temporarias += "\t" + $1.tipo + " " + realLabel + ";\n";

    string trad = $4.traducao;
    string labelDireito = tirarCastSeNecessario($1.tipo, $4.tipo, $4.label, trad);
    $$.traducao = trad + "\t" + realLabel + " = " + labelDireito + ";\n";
}
| tipo TK_ID '[' E ']'
{
    if ($4.tipo != "int") erroSemantico("Tamanho do vetor deve ser um numero inteiro.");
    Variavel v = buscarVariavel($2.label);
    if (v.tipo != "" && pilhaEscopos.top().find($2.label) != pilhaEscopos.top().end()) {
        erroSemantico("Variavel '" + $2.label + "' ja declarada neste escopo.");
    }
    string varLabel = gentempcode();
    declararVariavelArray($2.label, $1.tipo, varLabel, 1);
    vars_temporarias += "\t" + $1.tipo + "* " + varLabel + ";\n";
    $$.traducao = $4.traducao + "\t" + varLabel + " = (" + $1.tipo + "*) malloc(" + $4.label + " * sizeof(" + $1.tipo + "));\n";
}
| tipo TK_ID '[' E ']' '[' E ']'
{
    if ($4.tipo != "int" || $7.tipo != "int") erroSemantico("Tamanhos da matriz devem ser inteiros.");
    string varLabel = gentempcode();
    string colSize = gentempcode();
    vars_temporarias += "\tint " + colSize + ";\n";
    string trad = $4.traducao + $7.traducao + "\t" + colSize + " = " + $7.label + ";\n";
    declararVariavelArray($2.label, $1.tipo, varLabel, 2, colSize);
    vars_temporarias += "\t" + $1.tipo + "* " + varLabel + ";\n";
    string totalSize = gentempcode();
    vars_temporarias += "\tint " + totalSize + ";\n";
    trad += "\t" + totalSize + " = " + $4.label + " * " + colSize + ";\n";
    trad += "\t" + varLabel + " = (" + $1.tipo + "*) malloc(" + totalSize + " * sizeof(" + $1.tipo + "));\n";
    $$.traducao = trad;
}
| TK_VAR TK_ID TK_ATRIB E
{
    Variavel v = buscarVariavel($2.label);
    if (v.tipo != "" && pilhaEscopos.top().find($2.label) != pilhaEscopos.top().end()) {
        erroSemantico("Variavel '" + $2.label + "' ja declarada neste escopo.");
    }
    string tipoInferido = $4.tipo;
    string realLabel = $2.label + "_" + to_string(linha);
    declararVariavel($2.label, tipoInferido, realLabel);
    vars_temporarias += "\t" + tipoInferido + " " + realLabel + ";\n";
    $$.traducao = $4.traducao + "\t" + realLabel + " = " + $4.label + ";\n";
}
| TK_VAR TK_ID
{
    erroSemantico("Variavel '" + $2.label + "' declarada com 'var' precisa ser inicializada (ex: var " + $2.label + " = valor;).");
}
| TK_VAR TK_ID '[' E ']'
{
    erroSemantico("'var' nao pode ser usado para declarar arrays; especifique o tipo explicitamente (ex: int " + $2.label + "[" + $4.label + "];).");
}
;

atribuicao : TK_ID TK_ATRIB E
{
    Variavel v = buscarVariavel($1.label);
    if (v.tipo == "") erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    if (v.is_array != 0) erroSemantico("Nao e possivel atribuir um valor escalar para um array estruturado.");
    
    string trad = $3.traducao;
    string labelDireito = tirarCastSeNecessario(v.tipo, $3.tipo, $3.label, trad);
    $$.traducao = trad + "\t" + v.label + " = " + labelDireito + ";\n";
}
| TK_ID '[' E ']' TK_ATRIB E
{
    Variavel v = buscarVariavel($1.label);
    if (v.tipo == "") erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    if (v.is_array != 1) erroSemantico("A variavel '" + $1.label + "' nao e um arranjo unidimensional.");
    if ($3.tipo != "int") erroSemantico("O indice do vetor deve ser inteiro.");
    
    string trad = $3.traducao + $6.traducao;
    string labelDireito = tirarCastSeNecessario(v.tipo, $6.tipo, $6.label, trad);
    $$.traducao = trad + "\t" + v.label + "[" + $3.label + "] = " + labelDireito + ";\n";
}
| TK_ID '[' E ']' '[' E ']' TK_ATRIB E
{
    Variavel v = buscarVariavel($1.label);
    if (v.tipo == "") erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    if (v.is_array != 2) erroSemantico("A variavel '" + $1.label + "' nao e uma matriz bidimensional.");
    if ($3.tipo != "int" || $6.tipo != "int") erroSemantico("Os indices de matriz devem ser inteiros.");
    
    string idxLinear = gentempcode();
    vars_temporarias += "\tint " + idxLinear + ";\n";
    
    string trad = $3.traducao + $6.traducao + $9.traducao;
    trad += "\t" + idxLinear + " = (" + $3.label + " * " + v.col_size + ") + " + $6.label + ";\n";
    string labelDireito = tirarCastSeNecessario(v.tipo, $9.tipo, $9.label, trad);
    $$.traducao = trad + "\t" + v.label + "[" + idxLinear + "] = " + labelDireito + ";\n";
}
| atribuicao_composta { $$.traducao = $1.traducao; }
;

atribuicao_composta : TK_ID TK_MAIS_IGUAL E  { $$.traducao = gerarAtribuicaoComposta($1.label, "+", $3); }
                    | TK_ID TK_MENOS_IGUAL E { $$.traducao = gerarAtribuicaoComposta($1.label, "-", $3); }
                    | TK_ID TK_VEZES_IGUAL E { $$.traducao = gerarAtribuicaoComposta($1.label, "*", $3); }
                    | TK_ID TK_DIV_IGUAL E   { $$.traducao = gerarAtribuicaoComposta($1.label, "/", $3); }
                    | TK_ID '[' E ']' TK_MAIS_IGUAL E  { $$.traducao = gerarAtribuicaoCompostaArray($1.label, $3, "+", $6); }
                    | TK_ID '[' E ']' TK_MENOS_IGUAL E { $$.traducao = gerarAtribuicaoCompostaArray($1.label, $3, "-", $6); }
                    | TK_ID '[' E ']' TK_VEZES_IGUAL E { $$.traducao = gerarAtribuicaoCompostaArray($1.label, $3, "*", $6); }
                    | TK_ID '[' E ']' TK_DIV_IGUAL E   { $$.traducao = gerarAtribuicaoCompostaArray($1.label, $3, "/", $6); }
                    | TK_ID '[' E ']' '[' E ']' TK_MAIS_IGUAL E  { $$.traducao = gerarAtribuicaoCompostaMatriz($1.label, $3, $6, "+", $9); }
                    | TK_ID '[' E ']' '[' E ']' TK_MENOS_IGUAL E { $$.traducao = gerarAtribuicaoCompostaMatriz($1.label, $3, $6, "-", $9); }
                    | TK_ID '[' E ']' '[' E ']' TK_VEZES_IGUAL E { $$.traducao = gerarAtribuicaoCompostaMatriz($1.label, $3, $6, "*", $9); }
                    | TK_ID '[' E ']' '[' E ']' TK_DIV_IGUAL E   { $$.traducao = gerarAtribuicaoCompostaMatriz($1.label, $3, $6, "/", $9); }
                    ;

condicional : TK_IF '(' E ')' bloco TK_ELSE bloco
            {
                if ($3.tipo != "bool") erroSemantico("A expressao do 'if' deve ser booleana.");
                string Ltrue = genlabel();
                string Lfalse = genlabel();
                string Lend = genlabel();
                $$.traducao = $3.traducao + "\tif (" + $3.label + ") goto " + Ltrue + ";\n\tgoto " + Lfalse + ";\n" + Ltrue + ":;\n" + $5.traducao + "\tgoto " + Lend + ";\n" + Lfalse + ":;\n" + $7.traducao + Lend + ":;\n";
            }
            | TK_IF '(' E ')' bloco
            {
                if ($3.tipo != "bool") erroSemantico("A expressao do 'if' deve ser booleana.");
                string Ltrue = genlabel();
                string Lend = genlabel();
                
                $$.traducao = $3.traducao + "\tif (" + $3.label + ") goto " + Ltrue + ";\n\tgoto " + Lend + ";\n" + Ltrue + ":;\n" + $5.traducao + Lend + ":;\n";
            }
            ;

bloco : comando { $$.traducao = $1.traducao; } ;

iterativo : TK_WHILE {
                $$.label = genlabel();    // Guarda Lcond em $2.label
                $$.traducao = genlabel(); // Guarda Lend em $2.traducao
                stack_break.push($$.traducao);
                stack_continue.push($$.label);
            } '(' E ')' bloco
            {
                if ($4.tipo != "bool") erroSemantico("A expressao do 'while' deve ser booleana.");
                string Lcond = $2.label;
                string Lend = $2.traducao;
                string Ltrue = genlabel();
                
                $$.traducao = Lcond + ":;\n" + $4.traducao + "\tif (" + $4.label + ") goto " + Ltrue + ";\n\tgoto " + Lend + ";\n" + Ltrue + ":;\n" + $6.traducao + "\tgoto " + Lcond + ";\n" + Lend + ":;\n";
                
                stack_break.pop();
                stack_continue.pop();
            }
            | TK_DO {
                $$.label = genlabel();       // Guarda Lloop em $2.label
                $$.traducao = genlabel();    // Guarda Lend em $2.traducao
                $$.tipo = genlabel();        // Guarda Lcond em $2.tipo
                stack_break.push($$.traducao);
                stack_continue.push($$.tipo);
            } bloco TK_WHILE '(' E ')' ';'
            {
                if ($6.tipo != "bool") erroSemantico("A expressao do 'do-while' deve ser booleana.");
                string Lloop = $2.label;
                string Lend = $2.traducao;
                string Lcond = $2.tipo;

                $$.traducao = Lloop + ":;\n" + $3.traducao + Lcond + ":;\n" + $6.traducao + "\tif (" + $6.label + ") goto " + Lloop + ";\n" + Lend + ":;\n";
                stack_break.pop();
                stack_continue.pop();
            }
            | TK_FOR '(' inicializacao_opcional ';' {
                $$.label = genlabel();    // Guarda Lcond em $5.label
                $$.traducao = genlabel(); // Guarda Lend em $5.traducao
                stack_break.push($$.traducao);
            } expressao_opcional ';' {
                $$.label = genlabel();    // Guarda Lstep em $8.label
                stack_continue.push($$.label);
            } atualizacao_opcional ')' bloco
            {
                string Lcond = $5.label;
                string Lend = $5.traducao;
                string Lstep = $8.label;
                string Lloop = genlabel();
                
                string tradCond = ($6.label == "") ? "" : $6.traducao;
                string checkCond = ($6.label == "") ? "\tgoto " + Lloop + ";\n" : "\tif (" + $6.label + ") goto " + Lloop + ";\n\tgoto " + Lend + ";\n";
                
                $$.traducao = $3.traducao + Lcond + ":;\n" + tradCond + checkCond + Lstep + ":;\n" + $9.traducao + "\tgoto " + Lcond + ";\n" + Lloop + ":;\n" + $11.traducao + "\tgoto " + Lstep + ";\n" + Lend + ":;\n";
                stack_break.pop();
                stack_continue.pop();
            }
            | TK_FOREACH '(' tipo TK_ID ':' TK_ID ',' E ')'
            {
                Variavel v = buscarVariavel($6.label);
                if (v.tipo == "") erroSemantico("Variavel '" + $6.label + "' nao declarada.");
                if (v.is_array != 1) erroSemantico("'" + $6.label + "' nao e um arranjo unidimensional, foreach exige um array 1D.");
                if (v.tipo != $3.tipo) erroSemantico("Tipo do item do foreach (" + $3.tipo + ") incompativel com o tipo do array '" + $6.label + "' (" + v.tipo + ").");
                if ($8.tipo != "int") erroSemantico("O tamanho informado no foreach deve ser um numero inteiro.");

                DadosForeach d;
                d.Lcond = genlabel();
                d.Lstep = genlabel();
                d.Lend = genlabel();
                d.Ltrue = genlabel();
                d.tamTrad = $8.traducao;
                d.tamLabel = $8.label;
                d.arrLabel = v.label;

                stack_break.push(d.Lend);
                stack_continue.push(d.Lstep);

                entrarEscopo();

                d.idxLabel = gentempcode();
                vars_temporarias += "\tint " + d.idxLabel + ";\n";

                d.itemLabel = $4.label + "_" + to_string(linha);
                declararVariavel($4.label, $3.tipo, d.itemLabel);
                vars_temporarias += "\t" + $3.tipo + " " + d.itemLabel + ";\n";

                stack_foreach.push(d);
            }
            bloco
            {
                DadosForeach d = stack_foreach.top();
                stack_foreach.pop();

                string trad = d.tamTrad;
                trad += "\t" + d.idxLabel + " = 0;\n";
                trad += d.Lcond + ":;\n";
                trad += "\tif (" + d.idxLabel + " < " + d.tamLabel + ") goto " + d.Ltrue + ";\n";
                trad += "\tgoto " + d.Lend + ";\n";
                trad += d.Ltrue + ":;\n";
                trad += "\t" + d.itemLabel + " = " + d.arrLabel + "[" + d.idxLabel + "];\n";
                trad += $11.traducao;
                trad += d.Lstep + ":;\n";
                trad += "\t" + d.idxLabel + " = " + d.idxLabel + " + 1;\n";
                trad += "\tgoto " + d.Lcond + ";\n";
                trad += d.Lend + ":;\n";

                $$.traducao = trad;

                sairEscopo();
                stack_break.pop();
                stack_continue.pop();
            }
            ;

inicializacao_opcional : atribuicao { $$.traducao = $1.traducao; }
                       | /* vazio */ { $$.traducao = ""; }
                       ;

expressao_opcional : E { $$.traducao = $1.traducao; $$.label = $1.label; $$.tipo = $1.tipo; }
                   | /* vazio */ { $$.traducao = ""; $$.label = ""; $$.tipo = "bool"; }
                   ;

atualizacao_opcional : atribuicao { $$.traducao = $1.traducao; }
                     | /* vazio */ { $$.traducao = ""; }
                     ;

estrutura_switch : TK_SWITCH '(' E ')' {
                    $$.traducao = genlabel(); // Guarda Lend em $5.traducao
                    stack_break.push($$.traducao);
                    stack_switch_expr.push($3.label);
                    
                    string firstFlag = gentempcode();
                    vars_temporarias += "\tbool " + firstFlag + ";\n";
                    stack_switch_flag.push(firstFlag);
                    
                    $$.label = $3.traducao + "\t" + firstFlag + " = false;\n"; // Salva instrução inicial em $5.label
                 } '{' lista_cases '}'
                 {
                    string Lend = $5.traducao;
                    string initTrad = $5.label;
                    $$.traducao = initTrad + $7.traducao + Lend + ":;\n";
                    
                    stack_break.pop();
                    stack_switch_expr.pop();
                    stack_switch_flag.pop();
                 }
                 ;

lista_cases : lista_cases item_case { $$.traducao = $1.traducao + $2.traducao; }
            | item_case { $$.traducao = $1.traducao; }
            ;

item_case : TK_CASE TK_NUM ':' {
                $$.label = genlabel();    // Guarda Lnext em $4.label
                $$.traducao = genlabel(); // Guarda Lbody em $4.traducao
                string expr_atual = stack_switch_expr.top();
                string flag_atual = stack_switch_flag.top();
                
                string trad = "\tif (" + flag_atual + ") goto " + $$.traducao + ";\n";
                trad += "\tif (" + expr_atual + " == " + $2.label + ") goto " + $$.traducao + ";\n";
                trad += "\tgoto " + $$.label + ";\n";
                trad += $$.traducao + ":;\n";
                trad += "\t" + flag_atual + " = true;\n";
                
                $$.tipo = trad; // Guarda as instruções de setup do case no atributo tipo
            } lista_comandos
          {
                string Lnext = $4.label;
                string caseInitTrad = $4.tipo;
                $$.traducao = caseInitTrad + $5.traducao + Lnext + ":;\n";
          }
          | TK_DEFAULT ':' lista_comandos
          {
                $$.traducao = $3.traducao;
          }
          ;

E : E '+' E          { $$.traducao = gerarOperacaoAritmetica("+", $1, $3, $$); }
  | E '-' E          { $$.traducao = gerarOperacaoAritmetica("-", $1, $3, $$); }
  | E '*' E          { $$.traducao = gerarOperacaoAritmetica("*", $1, $3, $$); }
  | E '/' E          { $$.traducao = gerarOperacaoAritmetica("/", $1, $3, $$); }
  | TK_INC TK_ID     {
        Variavel v = buscarVariavel($2.label);

        if (v.tipo == "")
            erroSemantico("Variavel '" + $2.label + "' nao declarada.");

        if (v.tipo != "int" && v.tipo != "float")
            erroSemantico("Operador ++ exige operando numerico.");

        $$.tipo = v.tipo;
        $$.label = gentempcode();

        vars_temporarias += "\t" + v.tipo + " " + $$.label + ";\n";

        string um = (v.tipo == "float") ? "1.0" : "1";

        $$.traducao =
            "\t" + v.label + " = " + v.label + " + " + um + ";\n" +
            "\t" + $$.label + " = " + v.label + ";\n";
    }
   | TK_ID TK_INC    {
        Variavel v = buscarVariavel($1.label);

        if (v.tipo == "")
            erroSemantico("Variavel '" + $1.label + "' nao declarada.");

        if (v.tipo != "int" && v.tipo != "float")
            erroSemantico("Operador ++ exige operando numerico.");

        $$.tipo = v.tipo;
        $$.label = gentempcode();

        vars_temporarias += "\t" + v.tipo + " " + $$.label + ";\n";

        string um = (v.tipo == "float") ? "1.0" : "1";

        $$.traducao =
            "\t" + $$.label + " = " + v.label + ";\n" +
            "\t" + v.label + " = " + v.label + " + " + um + ";\n";
    }
  | TK_DEC TK_ID     {
        Variavel v = buscarVariavel($2.label);

        if (v.tipo == "")
            erroSemantico("Variavel '" + $2.label + "' nao declarada.");

        if (v.tipo != "int" && v.tipo != "float")
            erroSemantico("Operador -- exige operando numerico.");

        $$.tipo = v.tipo;
        $$.label = gentempcode();

        vars_temporarias += "\t" + v.tipo + " " + $$.label + ";\n";

        string um = (v.tipo == "float") ? "1.0" : "1";

        $$.traducao =
            "\t" + v.label + " = " + v.label + " - " + um + ";\n" +
            "\t" + $$.label + " = " + v.label + ";\n";
    }
  | TK_ID TK_DEC     {
        Variavel v = buscarVariavel($1.label);

        if (v.tipo == "")
            erroSemantico("Variavel '" + $1.label + "' nao declarada.");

        if (v.tipo != "int" && v.tipo != "float")
            erroSemantico("Operador -- exige operando numerico.");

        $$.tipo = v.tipo;
        $$.label = gentempcode();

        vars_temporarias += "\t" + v.tipo + " " + $$.label + ";\n";

        string um = (v.tipo == "float") ? "1.0" : "1";

        $$.traducao =
            "\t" + $$.label + " = " + v.label + ";\n" +
            "\t" + v.label + " = " + v.label + " - " + um + ";\n";
    }
  | E TK_MOD E       { $$.traducao = gerarOperacaoMod($1, $3, $$); }
  | E TK_POW E       { $$.traducao = gerarOperacaoPotencia($1, $3, $$); }
  | E TK_IGUAL E     { $$.traducao = gerarOperacaoRelacional("==", $1, $3, $$); }
  | E TK_DIFERENTE E { $$.traducao = gerarOperacaoRelacional("!=", $1, $3, $$); }
  | E '<' E          { $$.traducao = gerarOperacaoRelacional("<",  $1, $3, $$); }
  | E '>' E          { $$.traducao = gerarOperacaoRelacional(">",  $1, $3, $$); }
  | E TK_MENOR_IGUAL E { $$.traducao = gerarOperacaoRelacional("<=", $1, $3, $$); }
  | E TK_MAIOR_IGUAL E { $$.traducao = gerarOperacaoRelacional(">=", $1, $3, $$); }
  | E TK_E E         { $$.traducao = gerarOperacaoLogica("&&", $1, $3, $$); }
  | E TK_OU E        { $$.traducao = gerarOperacaoLogica("||", $1, $3, $$); }
  | TK_NAO E         { 
        if ($2.tipo != "bool") erroSemantico("Operador '!' exige operando booleano.");
        $$.label = gentempcode(); vars_temporarias += "\tbool " + $$.label + ";\n"; $$.tipo = "bool";
        $$.traducao = $2.traducao + "\t" + $$.label + " = !" + $2.label + ";\n"; 
    }
  | '-' E %prec UMENOS
    {
        if ($2.tipo != "int" && $2.tipo != "float") erroSemantico("Operador unario '-' exige operando numerico (int ou float).");
        $$.tipo = $2.tipo;
        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
        $$.traducao = $2.traducao + "\t" + $$.label + " = -" + $2.label + ";\n";
    }
  | '+' E %prec UMAIS
    {
        if ($2.tipo != "int" && $2.tipo != "float") erroSemantico("Operador unario '+' exige operando numerico (int ou float).");
        $$.tipo = $2.tipo;
        $$.label = $2.label;
        $$.traducao = $2.traducao;
    }
  | '(' E ')'        { $$.label = $2.label; $$.traducao = $2.traducao; $$.tipo = $2.tipo; }
  | TK_NUM           { $$.label = $1.label; $$.traducao = ""; $$.tipo = $1.tipo; }
  | TK_TRUE          { $$.label = "true"; $$.traducao = ""; $$.tipo = "bool"; }
  | TK_FALSE         { $$.label = "false"; $$.traducao = ""; $$.tipo = "bool"; }
  | TK_ID
    {
        Variavel v = buscarVariavel($1.label);
        if (v.tipo == "") erroSemantico("Variavel '" + $1.label + "' nao declarada.");
        if (v.is_array != 0) erroSemantico("O identificador '" + $1.label + "' refere-se a um arranjo estruturado, use indices.");
        $$.label = v.label;
        $$.traducao = "";
        $$.tipo = v.tipo;
    }
  | TK_ID '[' E ']'
    {
        Variavel v = buscarVariavel($1.label);
        if (v.tipo == "") erroSemantico("Variavel '" + $1.label + "' nao declarada.");
        if (v.is_array != 1) erroSemantico("A variavel '" + $1.label + "' nao e um arranjo unidimensional.");
        if ($3.tipo != "int") erroSemantico("O indice do vetor deve ser inteiro.");
        
        $$.label = gentempcode();
        vars_temporarias += "\t" + v.tipo + " " + $$.label + ";\n";
        $$.tipo = v.tipo;
        $$.traducao = $3.traducao + "\t" + $$.label + " = " + v.label + "[" + $3.label + "];\n";
    }
  | TK_ID '[' E ']' '[' E ']'
    {
        Variavel v = buscarVariavel($1.label);
        if (v.tipo == "") erroSemantico("Variavel '" + $1.label + "' nao declarada.");
        if (v.is_array != 2) erroSemantico("A variavel '" + $1.label + "' nao e uma matriz bidimensional.");
        if ($3.tipo != "int" || $6.tipo != "int") erroSemantico("Os indices de matriz devem ser inteiros.");
        
        string idxLinear = gentempcode();
        vars_temporarias += "\tint " + idxLinear + ";\n";
        
        $$.label = gentempcode();
        vars_temporarias += "\t" + v.tipo + " " + $$.label + ";\n";
        $$.tipo = v.tipo;
        string trad = $3.traducao + $6.traducao;
        trad += "\t" + idxLinear + " = (" + $3.label + " * " + v.col_size + ") + " + $6.label + ";\n";
        trad += "\t" + $$.label + " = " + v.label + "[" + idxLinear + "];\n";
        $$.traducao = trad;
    }
  | TK_ID '(' lista_args_opcional ')'
    {
        if (tabelaFuncoes.find($1.label) == tabelaFuncoes.end()) erroSemantico("Funcao '" + $1.label + "' nao declarada.");
        Funcao f = tabelaFuncoes[$1.label];
        if (f.tipoRetorno == "void") erroSemantico("Funcao 'void' '" + $1.label + "' nao pode ser usada em uma expressao.");
        if (f.tiposParam.size() != $3.listaTipos.size()) erroSemantico("Numero incorreto de argumentos na chamada de '" + $1.label + "'.");

        string trad = $3.traducao;
        string argsC = "";
        for (size_t i = 0; i < f.tiposParam.size(); i++) {
            string labelArg = tirarCastSeNecessario(f.tiposParam[i], $3.listaTipos[i], $3.listaLabels[i], trad);
            argsC += (i > 0 ? ", " : "") + labelArg;
        }

        $$.tipo = f.tipoRetorno;
        $$.label = gentempcode();
        vars_temporarias += "\t" + f.tipoRetorno + " " + $$.label + ";\n";
        $$.traducao = trad + "\t" + $$.label + " = " + f.labelC + "(" + argsC + ");\n";
    }
  ;

%%

/* IMPLEMENTAÇÃO DAS FUNÇÕES */
string gentempcode() { return "t" + to_string(var_temp_qnt++); }
string genlabel() { return "L" + to_string(label_qnt++); }
/* yyerror e erroSemantico já foram definidos no bloco de prólogo acima */

string gerarCast(string label_origem, string tipo_origem, string tipo_destino, string &traducao_acumulada) {
    if (tipo_origem == tipo_destino) return label_origem;
    string novoLabel = gentempcode();
    vars_temporarias += "\t" + tipo_destino + " " + novoLabel + ";\n";
    traducao_acumulada += "\t" + novoLabel + " = (" + tipo_destino + ") " + label_origem + ";\n";
    return novoLabel;
}

string tirarCastSeNecessario(string tipoDestino, string tipoOrigem, string labelOrigem, string &traducao) {
    if (tipoDestino == "float" && tipoOrigem == "int") {
        return gerarCast(labelOrigem, "int", "float", traducao);
    }
    if (tipoDestino == "int" && tipoOrigem == "float") {
        return gerarCast(labelOrigem, "float", "int", traducao);
    }
    if (tipoDestino != tipoOrigem) {
        erroSemantico("Tipos incompativeis. Incompatibilidade entre " + tipoDestino + " e " + tipoOrigem);
    }
    return labelOrigem;
}
string gerarOperacaoAritmetica(string op, atributos e1, atributos e3, atributos &res) {
    string trad = e1.traducao + e3.traducao;
    string t1 = e1.tipo, t3 = e3.tipo;
    
    if ((t1 != "int" && t1 != "float") || (t3 != "int" && t3 != "float")) {
        erroSemantico("Operadores aritmeticos nao suportados para os tipos informados.");
    }
    
    res.tipo = (t1 == "float" || t3 == "float") ? "float" : "int";
    res.label = gentempcode();
    vars_temporarias += "\t" + res.tipo + " " + res.label + ";\n";
    string l1 = gerarCast(e1.label, t1, res.tipo, trad);
    string l3 = gerarCast(e3.label, t3, res.tipo, trad);
    return trad + "\t" + res.label + " = " + l1 + " " + op + " " + l3 + ";\n";
}

string gerarOperacaoRelacional(string op, atributos e1, atributos e3, atributos &res) {
    bool algumBool = (e1.tipo == "bool" || e3.tipo == "bool");
    bool ambosBool = (e1.tipo == "bool" && e3.tipo == "bool");
    if (algumBool && !ambosBool) {
        erroSemantico("Nao e possivel comparar o tipo 'bool' com o tipo '" + (e1.tipo == "bool" ? e3.tipo : e1.tipo) + "'.");
    }

    string trad = e1.traducao + e3.traducao;
    string t_maior = (e1.tipo == "float" || e3.tipo == "float") ? "float" : (ambosBool ? "bool" : "int");

    res.tipo = "bool";
    res.label = gentempcode();
    vars_temporarias += "\tbool " + res.label + ";\n";

    string l1 = ambosBool ? e1.label : gerarCast(e1.label, e1.tipo, t_maior, trad);
    string l3 = ambosBool ? e3.label : gerarCast(e3.label, e3.tipo, t_maior, trad);

    return trad + "\t" + res.label + " = " + l1 + " " + op + " " + l3 + ";\n";
}

string gerarOperacaoLogica(string op, atributos e1, atributos e3, atributos &res) {
    if (e1.tipo != "bool" || e3.tipo != "bool") erroSemantico("Operadores logicos exigem operandos booleanos.");
    res.tipo = "bool";
    res.label = gentempcode();
    vars_temporarias += "\tbool " + res.label + ";\n";
    return e1.traducao + e3.traducao + "\t" + res.label + " = " + e1.label + " " + op + " " + e3.label + ";\n";
}

string gerarAtribuicaoComposta(string varNome, string op, atributos e) {
    Variavel v = buscarVariavel(varNome);
    if (v.tipo == "") erroSemantico("Variavel '" + varNome + "' nao declarada.");
    
    atributos e_var;
    e_var.label = v.label;
    e_var.tipo = v.tipo;
    e_var.traducao = "";
    
    atributos res_op;
    string trad = gerarOperacaoAritmetica(op, e_var, e, res_op);
    string labelFinal = tirarCastSeNecessario(v.tipo, res_op.tipo, res_op.label, trad);
    return trad + "\t" + v.label + " = " + labelFinal + ";\n";
}

string gerarAtribuicaoCompostaArray(string varNome, atributos idx, string op, atributos e) {
    Variavel v = buscarVariavel(varNome);
    if (v.tipo == "") erroSemantico("Variavel '" + varNome + "' nao declarada.");
    if (idx.tipo != "int") erroSemantico("O indice do vetor deve ser inteiro.");
    
    string t_val = gentempcode();
    vars_temporarias += "\t" + v.tipo + " " + t_val + ";\n";
    string trad_leitura = idx.traducao + "\t" + t_val + " = " + v.label + "[" + idx.label + "];\n";
    atributos e_arr;
    e_arr.label = t_val;
    e_arr.tipo = v.tipo;
    e_arr.traducao = trad_leitura;
    
    atributos res_op;
    string trad_op = gerarOperacaoAritmetica(op, e_arr, e, res_op) + e.traducao;
    string labelFinal = tirarCastSeNecessario(v.tipo, res_op.tipo, res_op.label, trad_op);
    return trad_op + "\t" + v.label + "[" + idx.label + "] = " + labelFinal + ";\n";
}

string gerarAtribuicaoCompostaMatriz(string varNome, atributos idxLinha, atributos idxColuna, string op, atributos e) {
    Variavel v = buscarVariavel(varNome);
    if (v.tipo == "") erroSemantico("Variavel '" + varNome + "' nao declarada.");
    if (v.is_array != 2) erroSemantico("A variavel '" + varNome + "' nao e uma matriz bidimensional.");
    if (idxLinha.tipo != "int" || idxColuna.tipo != "int") erroSemantico("Os indices de matriz devem ser inteiros.");

    string idxLinear = gentempcode();
    vars_temporarias += "\tint " + idxLinear + ";\n";
    string trad_idx = idxLinha.traducao + idxColuna.traducao;
    trad_idx += "\t" + idxLinear + " = (" + idxLinha.label + " * " + v.col_size + ") + " + idxColuna.label + ";\n";

    string t_val = gentempcode();
    vars_temporarias += "\t" + v.tipo + " " + t_val + ";\n";
    string trad_leitura = trad_idx + "\t" + t_val + " = " + v.label + "[" + idxLinear + "];\n";
    atributos e_mat;
    e_mat.label = t_val;
    e_mat.tipo = v.tipo;
    e_mat.traducao = trad_leitura;

    atributos res_op;
    string trad_op = gerarOperacaoAritmetica(op, e_mat, e, res_op) + e.traducao;
    string labelFinal = tirarCastSeNecessario(v.tipo, res_op.tipo, res_op.label, trad_op);
    return trad_op + "\t" + v.label + "[" + idxLinear + "] = " + labelFinal + ";\n";
}

string gerarOperacaoMod(atributos e1, atributos e3, atributos &res) {
    if (e1.tipo != "int" || e3.tipo != "int") erroSemantico("O operador de resto (%) exige operandos inteiros.");
    res.tipo = "int";
    res.label = gentempcode();
    vars_temporarias += "\tint " + res.label + ";\n";
    return e1.traducao + e3.traducao + "\t" + res.label + " = " + e1.label + " % " + e3.label + ";\n";
}

string gerarOperacaoPotencia(atributos e1, atributos e3, atributos &res) {
    string trad = e1.traducao + e3.traducao;
    string base = e1.label;
    string exp = e3.label;
    
    if (e3.tipo != "int") erroSemantico("O expoente da potencia (**) deve ser um numero inteiro.");
    if (e1.tipo == "float") {
        string i_f     = gentempcode();
        string res_f   = gentempcode();
        string Lloop_f = genlabel();
        string Lend_f  = genlabel();
        vars_temporarias += "\tint " + i_f   + ";\n";
        vars_temporarias += "\tfloat " + res_f + ";\n";
        trad += "\t" + res_f + " = 1.0;\n";
        trad += "\t" + i_f   + " = 0;\n";
        trad += Lloop_f + ":;\n";
        trad += "\tif (" + i_f + " >= " + exp + ") goto " + Lend_f + ";\n";
        trad += "\t" + res_f + " = " + res_f + " * " + base + ";\n";
        trad += "\t" + i_f   + " = " + i_f   + " + 1;\n";
        trad += "\tgoto " + Lloop_f + ";\n";
        trad += Lend_f + ":;\n";
        res.label = res_f;
    } else {
        string i     = gentempcode();
        string res_i = gentempcode();
        string Lloop = genlabel();
        string Lend  = genlabel();
        vars_temporarias += "\tint " + i   + ";\n";
        vars_temporarias += "\tint " + res_i + ";\n";
        trad += "\t" + res_i + " = 1;\n";
        trad += "\t" + i   + " = 0;\n";
        trad += Lloop + ":;\n";
        trad += "\tif (" + i + " >= " + exp + ") goto " + Lend + ";\n";
        trad += "\t" + res_i + " = " + res_i + " * " + base + ";\n";
        trad += "\t" + i   + " = " + i   + " + 1;\n";
        trad += "\tgoto " + Lloop + ";\n";
        trad += Lend + ":;\n";
        res.label = res_i;
    }
    res.tipo = e1.tipo;
    return trad;
}

void iniciarDeclaracaoFuncao(string nome, string tipoRetorno, vector<string> tiposParam, vector<string> nomesParam, atributos &dadosPendentes) {
    if (tabelaFuncoes.find(nome) != tabelaFuncoes.end()) {
        erroSemantico("Funcao '" + nome + "' ja declarada.");
    }
    Funcao f;
    f.tipoRetorno = tipoRetorno;
    f.tiposParam = tiposParam;
    f.nomesParam = nomesParam;
    f.labelC = "foca_" + nome;
    tabelaFuncoes[nome] = f;

    pilhaTipoRetornoAtual.push(tipoRetorno);
    entrarEscopo();
    pilhaVarsTemporarias.push_back("");

    string paramsC = "";
    for (size_t i = 0; i < f.tiposParam.size(); i++) {
        string labelParam = f.nomesParam[i] + "_p";
        declararVariavel(f.nomesParam[i], f.tiposParam[i], labelParam);
        paramsC += (i > 0 ? ", " : "") + f.tiposParam[i] + " " + labelParam;
    }

    // guarda dados pendentes para a regra final montar a funcao em C
    dadosPendentes.tipo = f.tipoRetorno;
    dadosPendentes.label = f.labelC;
    dadosPendentes.traducao = paramsC;
}

void finalizarDeclaracaoFuncao(atributos dadosPendentes, string corpoTraducao) {
    string tipoRetorno = dadosPendentes.tipo;
    string labelC = dadosPendentes.label;
    string paramsC = dadosPendentes.traducao;
    string declsLocais = pilhaVarsTemporarias.back();

    string assinatura = tipoRetorno + " " + labelC + "(" + paramsC + ")";
    funcoes_geradas += assinatura + " {\n" + declsLocais + "\n" + corpoTraducao;
    if (tipoRetorno == "void") {
        funcoes_geradas += "\treturn;\n";
    }
    funcoes_geradas += "}\n\n";

    pilhaVarsTemporarias.pop_back();
    sairEscopo();
    pilhaTipoRetornoAtual.pop();
}

int main() {
    var_temp_qnt = 0;
    int resultado = yyparse();
    if (resultado == 0 && !houveErro) {
        cout << codigo_gerado;
    }
    return (resultado != 0 || houveErro) ? 1 : 0;
}