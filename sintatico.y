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

int var_temp_qnt;
int label_qnt = 0; 
string codigo_gerado;
string vars_temporarias = ""; 

stack<string> stack_break;    // Pilha para o break
stack<string> stack_continue; // Pilha para o continue
stack<string> stack_switch_expr; // Guarda o valor que está a ser avaliado
stack<string> stack_switch_flag; // Guarda a flag do fall-through

extern int linha;

struct atributos {
    string label;
    string traducao;
    string tipo;
};

struct Variavel {
    string tipo;
    string label;
    int is_array; // 0 = escalar, 1 = vetor 1D, 2 = matriz 2D
    string col_size; // Guarda o tamanho da coluna para cálculo de matrizes 2D
};

stack<map<string, Variavel>> pilhaEscopos;

void entrarEscopo() { pilhaEscopos.push(map<string, Variavel>()); }
void sairEscopo() { pilhaEscopos.pop(); }

/* ===================== Suporte a Subprogramas (Funcoes) ===================== */

struct FuncInfo {
    string tipoRetorno;          // "void", "int", "float", "bool", "char"
    vector<string> tiposParam;   // tipos escalares dos parametros, na ordem
    bool definida;                // true depois que o corpo foi processado
};

map<string, FuncInfo> tabelaFuncoes;

// Pilha de buffers de variaveis temporarias: cada funcao tem o seu proprio bloco
// de declaracoes locais/temporarias, em vez de um unico buffer global (vars_temporarias
// continua existindo e representa o buffer da funcao "atual", no topo da pilha).
stack<string> pilhaBuffersTemp;

// Pilha com o tipo de retorno esperado pela funcao que esta sendo compilada agora.
// Permite checar semanticamente o comando 'return' e tambem detectar 'return' fora de funcao.
stack<string> pilhaTipoRetorno;

// Pilha com o label de saida (fim) de cada funcao, para o 'return' poder "goto" até o
// epilogo da funcao mesmo quando aparece no meio do codigo, antes do final do bloco.
stack<string> pilhaLabelFimFuncao;

// Pilha com o label da variavel que guarda o valor de retorno de cada funcao ativa
stack<string> pilhaLabelRetorno;

// Acumula (tipo, nome) dos parametros formais enquanto a lista de parametros de uma
// definicao de funcao esta sendo reconhecida. Empilha um vetor novo ao abrir os
// parenteses da funcao e usa o topo para ir agregando cada parametro.
stack<vector<pair<string,string>>> pilhaParamsFormais;

// Acumula os atributos (tipo/label/traducao) dos argumentos reais enquanto uma
// chamada de funcao esta sendo reconhecida em uma expressao.
stack<vector<atributos>> pilhaArgsReais;

// Guarda a assinatura C (ja montada como string) da funcao que esta sendo
// compilada agora, entre o fechamento dos parenteses dos parametros e o
// fechamento do Bloco do corpo da funcao.
stack<string> pilhaAssinaturasFuncao;

void erroSemantico(string msg);
Variavel* buscarVariavel(string nome);

FuncInfo* buscarFuncao(string nome) {
    auto it = tabelaFuncoes.find(nome);
    if (it == tabelaFuncoes.end()) return nullptr;
    return &it->second;
}

void declararAssinaturaFuncao(string nome, string tipoRetorno, vector<string> tiposParam) {
    if (tabelaFuncoes.count(nome)) {
        erroSemantico("Funcao '" + nome + "' ja foi declarada anteriormente.");
    }
    if (buscarVariavel(nome)) {
        erroSemantico("Identificador '" + nome + "' ja esta em uso como variavel.");
    }
    tabelaFuncoes[nome] = { tipoRetorno, tiposParam, false };
}

void marcarFuncaoDefinida(string nome) {
    tabelaFuncoes[nome].definida = true;
}

// Salva o buffer atual de variaveis temporarias (da funcao "de fora") e comeca um buffer
// novo e vazio para a funcao que esta sendo compilada agora.
void entrarFuncaoBuffer() {
    pilhaBuffersTemp.push(vars_temporarias);
    vars_temporarias = "";
}

// Devolve o buffer da funcao que acabou de ser compilada (para ser usado no corpo
// gerado dessa funcao) e restaura o buffer da funcao "de fora".
string sairFuncaoBuffer() {
    string bufferDaFuncao = vars_temporarias;
    vars_temporarias = pilhaBuffersTemp.top();
    pilhaBuffersTemp.pop();
    return bufferDaFuncao;
}

void declararVariavel(string nome, string tipo, string label) { 
    pilhaEscopos.top()[nome] = {tipo, label, 0, ""}; 
}

void declararVariavelArray(string nome, string tipo, string label, int is_array, string col_size) {
    pilhaEscopos.top()[nome] = {tipo, label, is_array, col_size};
}

// Pilha com a profundidade de pilhaEscopos no momento em que cada funcao foi
// aberta. Enquanto estivermos dentro de uma funcao, buscarVariavel nao deve
// atravessar essa fronteira: o corpo de uma funcao so pode ver seus proprios
// parametros e variaveis locais, nunca variaveis de fora (do main ou de outra
// funcao), exatamente como em C.
stack<size_t> pilhaFronteiraEscopoFuncao;

Variavel* buscarVariavel(string nome) {
    auto copia = pilhaEscopos;
    size_t limite = pilhaFronteiraEscopoFuncao.empty() ? 0 : pilhaFronteiraEscopoFuncao.top();
    while (copia.size() > limite) {
        if (copia.top().count(nome)) return &copia.top()[nome];
        copia.pop();
    }
    return nullptr;
}

string tipoResultante(string t1, string t2) {
    if (t1 == "void" || t2 == "void") return "erro";
    if (t1 == "bool" || t2 == "bool") return "erro";
    if (t1 == "char" || t2 == "char") return "erro"; 
    if (t1 == t2) return t1;
    if ((t1 == "float" && t2 == "int") || (t1 == "int" && t2 == "float")) return "float";
    return "erro";
}

void erroSemantico(string msg) { cerr << "Erro Semantico na linha " << linha << ": " << msg << endl; exit(1); }

string gentempcode();

string genlabel() { label_qnt++; return "L" + to_string(label_qnt); }

struct Cast { string label; string traducao; };
Cast gerarCast(string label, string tipoOriginal, string tipoDestino) {
    Cast c; c.label = label; c.traducao = "";
    if (tipoOriginal == "int" && tipoDestino == "float") {
        c.label = gentempcode();
        vars_temporarias += "\tfloat " + c.label + ";\n";
        c.traducao = "\t" + c.label + " = (float) " + label + ";\n";
    }
    return c;
}

// Gera o codigo de uma chamada de funcao ja validada (aridade e tipos de cada
// argumento), aplicando cast implicito int->float argumento a argumento quando
// necessario, igual ao que ja se faz para atribuicoes e operadores binarios.
// 'resultado' recebe o atributo de retorno preenchido (label/tipo) quando a
// funcao nao for void; para void, label fica vazio.
atributos gerarChamadaFuncao(string nomeFuncao, vector<atributos>& argumentos) {
    FuncInfo* f = buscarFuncao(nomeFuncao);
    if (!f) erroSemantico("Funcao '" + nomeFuncao + "' nao declarada.");

    if (argumentos.size() != f->tiposParam.size()) {
        erroSemantico("Funcao '" + nomeFuncao + "' espera " + to_string(f->tiposParam.size())
            + " argumento(s), mas foi chamada com " + to_string(argumentos.size()) + ".");
    }

    string trad = "";
    vector<string> labelsFinais;

    for (size_t i = 0; i < argumentos.size(); i++) {
        string tipoEsperado = f->tiposParam[i];
        atributos arg = argumentos[i];
        trad += arg.traducao;
        string lab = arg.label;

        if (tipoEsperado == "float" && arg.tipo == "int") {
            Cast c = gerarCast(arg.label, "int", "float");
            trad += c.traducao;
            lab = c.label;
        } else if (tipoEsperado != arg.tipo) {
            erroSemantico("Argumento " + to_string(i + 1) + " da funcao '" + nomeFuncao
                + "' tem tipo incompativel: esperado '" + tipoEsperado + "', encontrado '" + arg.tipo + "'.");
        }
        labelsFinais.push_back(lab);
    }

    string chamada = nomeFuncao + "(";
    for (size_t i = 0; i < labelsFinais.size(); i++) {
        if (i > 0) chamada += ", ";
        chamada += labelsFinais[i];
    }
    chamada += ")";

    atributos resultado;
    resultado.tipo = f->tipoRetorno;

    if (f->tipoRetorno == "void") {
        trad += "\t" + chamada + ";\n";
        resultado.label = "";
    } else {
        resultado.label = gentempcode();
        vars_temporarias += "\t" + f->tipoRetorno + " " + resultado.label + ";\n";
        trad += "\t" + resultado.label + " = " + chamada + ";\n";
    }
    resultado.traducao = trad;
    return resultado;
}

// abrirFuncao: chamada apos reconhecer "tipoRetorno nome (" e a lista de parametros
// (ja acumulada em pilhaParamsFormais.top()). Registra a assinatura, abre o escopo
// da funcao com sua fronteira, declara os parametros como variaveis locais e monta
// a assinatura C, deixando tudo pronto para o Bloco do corpo ser parseado.
string abrirFuncao(string tipoRet, string labelTipoC, string nome) {
    vector<pair<string,string>> params = pilhaParamsFormais.top();
    pilhaParamsFormais.pop();

    vector<string> tiposParam;
    for (auto& p : params) tiposParam.push_back(p.first);
    declararAssinaturaFuncao(nome, tipoRet, tiposParam);

    string assinatura = labelTipoC + " " + nome + "(";
    for (size_t i = 0; i < params.size(); i++) {
        if (i > 0) assinatura += ", ";
        assinatura += params[i].first + " p_" + params[i].second;
    }
    if (params.empty()) assinatura += "void";
    assinatura += ")";

    entrarEscopo();
    pilhaFronteiraEscopoFuncao.push(pilhaEscopos.size() - 1);
    entrarFuncaoBuffer();

    string labelRetorno = "";
    if (tipoRet != "void") {
        labelRetorno = gentempcode();
        vars_temporarias += "\t" + labelTipoC + " " + labelRetorno + ";\n";
    }
    string labelFim = "_miku_fim_" + nome;

    pilhaTipoRetorno.push(tipoRet);
    pilhaLabelFimFuncao.push(labelFim);
    pilhaLabelRetorno.push(labelRetorno);

    for (auto& p : params) {
        declararVariavel(p.second, p.first, "p_" + p.second);
    }

    pilhaAssinaturasFuncao.push(assinatura);
    return assinatura;
}

// fecharFuncao: chamada apos o Bloco do corpo ja ter sido traduzido (corpoTraduzido).
// Monta a funcao C completa (assinatura + locais + corpo + epilogo de retorno) e
// restaura todo o contexto (escopo, buffer de temporarios, pilhas de funcao).
string fecharFuncao(string nome, string corpoTraduzido) {
    string assinatura = pilhaAssinaturasFuncao.top();
    pilhaAssinaturasFuncao.pop();

    string labelRetorno = pilhaLabelRetorno.top();
    string labelFim = pilhaLabelFimFuncao.top();
    string tipoRet = pilhaTipoRetorno.top();

    string bufferLocal = sairFuncaoBuffer();

    string corpo = assinatura + " {\n" + bufferLocal + "\n" + corpoTraduzido
                 + labelFim + ":;\n"
                 + (tipoRet != "void" ? ("\treturn " + labelRetorno + ";\n") : "\treturn;\n")
                 + "}\n\n";

    marcarFuncaoDefinida(nome);

    sairEscopo();
    pilhaFronteiraEscopoFuncao.pop();
    pilhaTipoRetorno.pop();
    pilhaLabelFimFuncao.pop();
    pilhaLabelRetorno.pop();

    return corpo;
}

string gerarAtribuicaoComposta(string idLabel, string op, atributos exp) {
    Variavel* v = buscarVariavel(idLabel);
    if (!v) erroSemantico("Variavel '" + idLabel + "' nao declarada.");
    if (v->tipo == "string") erroSemantico("Operadores compostos nao suportados para strings.");
    if (exp.tipo == "void") erroSemantico("Nao e possivel usar o resultado de uma funcao 'void' em uma atribuicao composta.");

    string trad = exp.traducao;
    string lab = exp.label;

    if (v->tipo == "float" && exp.tipo == "int") {
        Cast c = gerarCast(exp.label, "int", "float");
        trad += c.traducao;
        lab = c.label;
    }

    string temp = gentempcode();
    vars_temporarias += "\t" + v->tipo + " " + temp + ";\n";
    trad += "\t" + temp + " = " + v->label + " " + op + " " + lab + ";\n";
    trad += "\t" + v->label + " = " + temp + ";\n";

    return trad;
}

string gerarAtribuicaoCompostaArray(string idLabel, string op, atributos exp1, atributos* exp2, atributos exp_val) {
    Variavel* v = buscarVariavel(idLabel);
    if (!v) erroSemantico("Variavel '" + idLabel + "' nao declarada.");
    if (v->tipo == "string") erroSemantico("Operadores compostos nao suportados para strings.");
    if (exp_val.tipo == "void") erroSemantico("Nao e possivel usar o resultado de uma funcao 'void' em uma atribuicao composta.");

    string trad = exp1.traducao;
    if (exp2) trad += exp2->traducao;
    trad += exp_val.traducao;

    string lab = exp_val.label;
    if (v->tipo == "float" && exp_val.tipo == "int") {
        Cast c = gerarCast(exp_val.label, "int", "float");
        trad += c.traducao;
        lab = c.label;
    }

    string temp = gentempcode();
    vars_temporarias += "\t" + v->tipo + " " + temp + ";\n";

    string indexStr;
    if (exp2) { // 2D Matriz
        string calcIndex = gentempcode();
        vars_temporarias += "\tint " + calcIndex + ";\n";
        trad += "\t" + calcIndex + " = " + exp1.label + " * " + v->col_size + " + " + exp2->label + ";\n";
        indexStr = "[" + calcIndex + "]";
    } else { // 1D Vetor
        indexStr = "[" + exp1.label + "]";
    }

    trad += "\t" + temp + " = " + v->label + indexStr + " " + op + " " + lab + ";\n";
    trad += "\t" + v->label + indexStr + " = " + temp + ";\n";

    return trad;
}

int yylex(void);
void yyerror(string);
extern FILE *yyin;
%}

%token TK_NUM TK_ID TK_TIPO_INT TK_TIPO_FLOAT TK_TIPO_BOOL TK_TIPO_CHAR
%token TK_TRUE TK_FALSE TK_ATRIB TK_E TK_OU TK_NAO TK_IGUAL TK_DIFERENTE
%token TK_MENOR_IGUAL TK_MAIOR_IGUAL TK_PRINT TK_READ
%token TK_IF TK_ELSE TK_WHILE TK_FOR TK_DO
%token TK_BREAK TK_CONTINUE
%token TK_SWITCH TK_CASE TK_DEFAULT
%token TK_TIPO_VOID TK_RETURN
%token TK_TIPO_STRING TK_STR_LITERAL
%token TK_MAIS_IGUAL TK_MENOS_IGUAL TK_VEZES_IGUAL TK_DIV_IGUAL
%token TK_POW TK_MOD

%nonassoc LOWER_THAN_ELSE
%nonassoc TK_ELSE

%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/' TK_MOD
%right TK_POW
%right TK_NAO UMINUS UPLUS
%right CAST

%start S

%%

S : lista_top {
    codigo_gerado = "/*__________________________\n\n★  MIKU COMPILER (^_^)  ★\n__________________________*/\n\n"
    "#include <stdio.h>\n"
    "#include <stdlib.h>\n"
    "#include <string.h>\n"
    "\nint _miku_len(char *s) {\n"
    "\tint i;\n"
    "\tchar c;\n"
    "\tint t1;\n"
    "\ti = 0;\n"
    "_miku_len_loop:;\n"
    "\tc = s[i];\n"
    "\tt1 = (c == 0);\n"
    "\tif (t1) goto _miku_len_end;\n"
    "\ti = i + 1;\n"
    "\tgoto _miku_len_loop;\n"
    "_miku_len_end:;\n"
    "\treturn i;\n"
    "}\n"
    "void _miku_strcpy_safe(char **d, int *c, char *s) {\n"
    "\tint n;\n"
    "\tint t2;\n"
    "\tint f;\n"
    "\tint t3;\n"
    "\tint t4;\n"
    "\tn = _miku_len(s);\n"
    "\tn = n + 1;\n"
    "_miku_cpy_loop:;\n"
    "\tt2 = (*c < n);\n"
    "\tif (!t2) goto _miku_cpy_end;\n"
    "\tf = n - (*c);\n"
    "\tt3 = (f < 500);\n"
    "\tif (!t3) goto _miku_cpy_big;\n"
    "\t*c = *c + 500;\n"
    "\tgoto _miku_cpy_loop;\n"
    "_miku_cpy_big:;\n"
    "\t*c = *c + 1000;\n"
    "\tgoto _miku_cpy_loop;\n"
    "_miku_cpy_end:;\n"
    "\t*d = (char *) realloc(*d, *c);\n"
    "\tstrcpy(*d, s);\n"
    "}\n"
    "void _miku_read_string(char **buf, int *cap) {\n"
    "\tint len;\n"
    "\tchar t5;\n"
    "\tint t6;\n"
    "\tint t7;\n"
    "\tint t8;\n"
    "\tint t9;\n"
    "\tlen = 0;\n"
    "_miku_rds_loop:;\n"
    "\tt5 = (char)0;\n"
    "\tfgets(*buf + len, *cap - len, stdin);\n"
    "\tlen = _miku_len(*buf);\n"
    "\tt5 = (*buf)[len - 1];\n"
    "\tt6 = (t5 == '\\n');\n"
    "\tif (!t6) goto _miku_rds_no_nl;\n"
    "\t(*buf)[len - 1] = '\\0';\n"
    "\tgoto _miku_rds_end;\n"
    "_miku_rds_no_nl:;\n"
    "\tt7 = (len > 4500);\n"
    "\tif (!t7) goto _miku_rds_grow;\n"
    "\tfprintf(stderr, \"Erro: string de input excede 4500 caracteres\\n\");\n"
    "\texit(1);\n"
    "_miku_rds_grow:;\n"
    "\t*cap = *cap * 2;\n"
    "\t*buf = (char *) realloc(*buf, *cap);\n"
    "\tgoto _miku_rds_loop;\n"
    "_miku_rds_end:;\n"
    "}\n"
    + $1.tipo  /* corpo das funcoes do usuario, ja traduzido para C, na ordem em que foram definidas */
    + "\nint main(void) {\n" + vars_temporarias + "\n" + $1.traducao + "\treturn 0;\n}\n";
} ;

/* lista_top.tipo = corpo das funcoes acumulado, na ordem de definicao (cada funcao
   so pode chamar funcoes ja definidas antes dela no arquivo-fonte, ou a si mesma
   recursivamente; nao ha suporte a chamada para frente nem a recursao mutua).
   lista_top.traducao = comandos soltos acumulados (corpo implicito da main) */
lista_top : lista_top unidade_top {
                $$.tipo  = $1.tipo  + $2.tipo;
                $$.traducao = $1.traducao + $2.traducao;
            }
          | { $$.tipo = ""; $$.traducao = ""; } ;

unidade_top : funcao  { $$.tipo = $1.tipo; $$.traducao = ""; }
            | comando  { $$.tipo = ""; $$.traducao = $1.traducao; } ;

lista_comandos : lista_comandos comando { $$.traducao = $1.traducao + $2.traducao; }
               |                        { $$.traducao = ""; } ;

comando : declaracao             { $$.traducao = $1.traducao; }
        | atribuicao             { $$.traducao = $1.traducao; }
        | E ';'                  { $$.traducao = $1.traducao; }
        | Bloco                  { $$.traducao = $1.traducao; }
        | TK_PRINT '(' E ')' ';' {
            if ($3.tipo == "void") erroSemantico("Nao e possivel imprimir o resultado de uma funcao 'void'.");
            string fmt;
            if ($3.tipo == "float") fmt = "%f";
            else if ($3.tipo == "string") fmt = "%s";
            else fmt = "%d";
            $$.traducao = $3.traducao + "\tprintf(\"" + fmt + "\\n\", " + $3.label + ");\n";
        }
        | TK_READ '(' TK_ID ')' ';' { 
            Variavel* v = buscarVariavel($3.label);
            if (!v) erroSemantico("Variavel nao declarada.");
            if (v->is_array != 0) erroSemantico("Faltam indices para leitura de vetor/matriz.");
            if (v->tipo == "string") {
                $$.traducao = "\t_miku_read_string(&" + v->label + ", &" + v->label + "_cap);\n";
            } else {
                string fmt = (v->tipo == "float") ? "%f" : "%d";
                $$.traducao = "\tscanf(\"" + fmt + "\", &" + v->label + ");\n";
            }
        }
        | TK_READ '(' TK_ID '[' E ']' ')' ';' {
            if ($5.tipo != "int") erroSemantico("Indice do vetor deve ser inteiro.");
            Variavel* v = buscarVariavel($3.label);
            if (!v || v->is_array != 1) erroSemantico("Variavel invalida ou nao eh vetor.");
            string fmt = (v->tipo == "float") ? "%f" : "%d";
            $$.traducao = $5.traducao + "\tscanf(\"" + fmt + "\", &" + v->label + "[" + $5.label + "]);\n";
        }
        | TK_READ '(' TK_ID '[' E ']' '[' E ']' ')' ';' {
            if ($5.tipo != "int" || $8.tipo != "int") erroSemantico("Indices da matriz devem ser inteiros.");
            Variavel* v = buscarVariavel($3.label);
            if (!v || v->is_array != 2) erroSemantico("Variavel invalida ou nao eh matriz.");
            string fmt = (v->tipo == "float") ? "%f" : "%d";
            string calcIndex = gentempcode();
            vars_temporarias += "\tint " + calcIndex + ";\n";
            string trad = $5.traducao + $8.traducao + "\t" + calcIndex + " = " + $5.label + " * " + v->col_size + " + " + $8.label + ";\n";
            $$.traducao = trad + "\tscanf(\"" + fmt + "\", &" + v->label + "[" + calcIndex + "]);\n";
        }
        | TK_BREAK ';' {
            if (stack_break.empty()) {
                erroSemantico("Comando 'break' fora de um laco de repeticao ou switch.");
            }
            // Break normal: joga para o topo da pilha (laço mais interno)
            $$.traducao = "\tgoto " + stack_break.top() + ";\n";
        }
        | TK_BREAK TK_NUM ';' {
            if (stack_break.empty()) {
                erroSemantico("Comando 'break' fora de um laco de repeticao ou switch.");
            }

            // Convertemos o valor do token (string) para inteiro (ex: "2" vira 2)
            int niveis = atoi($2.label.c_str());

            if (niveis <= 0) {
                erroSemantico("O nivel do break deve ser um numero maior que zero.");
            }
            if (niveis > stack_break.size()) {
                erroSemantico("Nivel de 'break' invalido. Tentou quebrar " + to_string(niveis) + " niveis, mas existem apenas " + to_string(stack_break.size()) + " lacos aninhados.");
            }

            // Para acessar o N-ésimo elemento da pilha, precisamos desempilhar temporariamente
            // os elementos superiores em uma pilha auxiliar.
            stack<string> pilha_aux;
            for (int i = 1; i < niveis; i++) {
                pilha_aux.push(stack_break.top());
                stack_break.pop();
            }

            // O topo agora é o label do laço que queremos quebrar!
            string label_alvo = stack_break.top();

            // Devolvemos os elementos extraídos de volta para a pilha original para não estragar o escopo
            while (!pilha_aux.empty()) {
                stack_break.push(pilha_aux.top());
                pilha_aux.pop();
            }

            // Gera o goto para o laço externo correto
            $$.traducao = "\tgoto " + label_alvo + ";\n";
        }
        | TK_CONTINUE ';' {
            if (stack_continue.empty()) erroSemantico("comando 'continue' fora de um laco de repeticao.");
            $$.traducao = "\tgoto " + stack_continue.top() + ";\n";
        }
        | TK_RETURN ';' {
            if (pilhaTipoRetorno.empty()) erroSemantico("comando 'return' fora de uma funcao.");
            if (pilhaTipoRetorno.top() != "void") {
                erroSemantico("Funcao deve retornar um valor do tipo '" + pilhaTipoRetorno.top() + "', mas 'return' foi usado sem expressao.");
            }
            $$.traducao = "\tgoto " + pilhaLabelFimFuncao.top() + ";\n";
        }
        | TK_RETURN E ';' {
            if (pilhaTipoRetorno.empty()) erroSemantico("comando 'return' fora de uma funcao.");
            string tipoEsperado = pilhaTipoRetorno.top();
            if (tipoEsperado == "void") {
                erroSemantico("Funcao do tipo 'void' nao pode retornar um valor.");
            }

            string trad = $2.traducao;
            string lab = $2.label;

            if (tipoEsperado == "float" && $2.tipo == "int") {
                Cast c = gerarCast($2.label, "int", "float");
                trad += c.traducao;
                lab = c.label;
            } else if (tipoEsperado != $2.tipo) {
                erroSemantico("Tipo de retorno incompativel: esperado '" + tipoEsperado + "', encontrado '" + $2.tipo + "'.");
            }

            trad += "\t" + pilhaLabelRetorno.top() + " = " + lab + ";\n";
            trad += "\tgoto " + pilhaLabelFimFuncao.top() + ";\n";
            $$.traducao = trad;
        }
        | TK_IF '(' E ')' Bloco %prec LOWER_THAN_ELSE {
            string l1 = genlabel();
            $$.traducao = $3.traducao + "\tif (!" + $3.label + ") goto " + l1 + ";\n" + $5.traducao + l1 + ":;\n";
        }
        | TK_IF '(' E ')' Bloco TK_ELSE Bloco {
            string l1 = genlabel(); string l2 = genlabel();
            $$.traducao = $3.traducao + "\tif (!" + $3.label + ") goto " + l1 + ";\n" + $5.traducao + "\tgoto " + l2 + ";\n" + l1 + ":;\n" + $7.traducao + l2 + ":;\n";
        }
        | TK_WHILE '(' E ')' {
            $$.label = genlabel();   
            $$.traducao = genlabel();
            stack_continue.push($$.label);
            stack_break.push($$.traducao);
        } Bloco {
            string start = $5.label;
            string end = $5.traducao;
            $$.traducao = start + ":;\n" + $3.traducao + "\tif (!" + $3.label + ") goto " + end + ";\n" + $6.traducao + "\tgoto " + start + ";\n" + end + ":;\n";
            stack_continue.pop(); stack_break.pop();
        }
        | TK_DO {
            $$.label = genlabel();    
            $$.traducao = genlabel(); 
            $$.tipo = genlabel();     
            stack_continue.push($$.traducao);
            stack_break.push($$.tipo);
        } Bloco TK_WHILE '(' E ')' ';' {
            string start = $2.label;
            string cont = $2.traducao;
            string end = $2.tipo;
            $$.traducao = start + ":;\n" + $3.traducao + cont + ":;\n" + $6.traducao + "\tif (" + $6.label + ") goto " + start + ";\n" + end + ":;\n";
            stack_continue.pop(); stack_break.pop();
        }
        | TK_FOR '(' atrib_base ';' E ';' {
            $$.label = genlabel();    
            $$.traducao = genlabel(); 
            $$.tipo = genlabel();     
            stack_continue.push($$.tipo);
            stack_break.push($$.traducao);
        } atrib_base ')' Bloco {
            string start = $7.label;
            string end = $7.traducao;
            string inc = $7.tipo;
            $$.traducao = $3.traducao + start + ":;\n" + $5.traducao + "\tif (!" + $5.label + ") goto " + end + ";\n" + $10.traducao + inc + ":;\n" + $8.traducao + "\tgoto " + start + ";\n" + end + ":;\n";
            stack_continue.pop(); stack_break.pop();
        }
        | TK_SWITCH '(' E ')' {
            string flag = gentempcode();
            vars_temporarias += "\tint " + flag + " = 0;\n";
            stack_switch_expr.push($3.label);
            stack_switch_flag.push(flag);
            $$.label = genlabel(); 
            stack_break.push($$.label);
        } '{' casos '}' {
            $$.traducao = $3.traducao + $7.traducao + $5.label + ":;\n";
            stack_switch_expr.pop(); stack_switch_flag.pop(); stack_break.pop();
        };

Bloco : '{' { entrarEscopo(); } lista_comandos '}' { $$.traducao = "\t{\n" + $3.traducao + "\t}\n"; sairEscopo(); };

casos : casos caso { $$.traducao = $1.traducao + $2.traducao; }
      | /* vazio */ { $$.traducao = ""; };

caso : TK_CASE TK_NUM ':' lista_comandos {
    string expr = stack_switch_expr.top();
    string flag = stack_switch_flag.top();
    string next_case = genlabel();
    $$.traducao = "\tif (" + expr + " == " + $2.label + ") " + flag + " = 1;\n" + "\tif (!" + flag + ") goto " + next_case + ";\n" + $4.traducao + next_case + ":;\n";
}
| TK_DEFAULT ':' lista_comandos {
    string flag = stack_switch_flag.top();
    string next_case = genlabel();
    $$.traducao = "\t" + flag + " = 1;\n" + "\tif (!" + flag + ") goto " + next_case + ";\n" + $3.traducao + next_case + ":;\n";
};

tipo : TK_TIPO_INT   { $$.tipo = "int";   $$.label = "int"; }
     | TK_TIPO_FLOAT { $$.tipo = "float"; $$.label = "float"; }
     | TK_TIPO_BOOL  { $$.tipo = "bool";  $$.label = "int"; }
     | TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; };

/* ===================== Argumentos de chamada de funcao ===================== */
/* Os atributos sao acumulados em pilhaArgsReais.top(), empilhado antes de
   'lista_argumentos' ser reconhecida (ver regra de chamada de funcao em E). */

lista_argumentos : argumentos_nao_vazios { }
                  | /* vazio, chamada sem argumentos */ { } ;

argumentos_nao_vazios : E {
                            pilhaArgsReais.top().push_back($1);
                        }
                       | argumentos_nao_vazios ',' E {
                            pilhaArgsReais.top().push_back($3);
                        } ;

/* ===================== Parametros formais de uma funcao ===================== */
/* Apenas escalares (int/float/bool/char) sao permitidos como parametro, nao
   vetores/matrizes. Os pares (tipo, nome) sao acumulados em pilhaParamsFormais.top(),
   empilhado antes de 'lista_parametros' ser reconhecida (ver regra 'funcao'). */

lista_parametros : parametros_nao_vazios { }
                  | /* vazio, funcao sem parametros */ { } ;

parametros_nao_vazios : parametro { }
                       | parametros_nao_vazios ',' parametro { } ;

parametro : tipo TK_ID {
                pilhaParamsFormais.top().push_back({$1.tipo, $2.label});
            } ;

/* ===================== Definicao de Subprograma (Funcao) ===================== */
/* funcao.label = prototipo C da funcao (assinatura ; ), para permitir chamadas
/* ===================== Definicao de Subprograma (Funcao) ===================== */
/* funcao.tipo = definicao completa da funcao em C (assinatura + corpo).
   Ha duas alternativas (tipo escalar e TK_TIPO_VOID) em vez de um nao-terminal
   "tipo_retorno" intermediario: um nao-terminal assim forcaria o parser a reduzir
   'tipo' antes de ver o TK_ID seguinte, o que cria conflito com 'declaracao'
   (que tambem comeca com 'tipo TK_ID'). Mantendo o terminal sem reducao precoce,
   o parser LALR(1) decide naturalmente ao ver '(' depois do TK_ID. */
funcao : tipo TK_ID '(' {
            pilhaParamsFormais.push(vector<pair<string,string>>());
        } lista_parametros ')' {
            abrirFuncao($1.tipo, $1.label, $2.label);
        } Bloco {
            $$.tipo = fecharFuncao($2.label, $8.traducao);
            $$.label = ""; // prototipos C nao sao necessarios: cada funcao referencia apenas funcoes ja definidas antes dela
            $$.traducao = "";
        }
       | TK_TIPO_VOID TK_ID '(' {
            pilhaParamsFormais.push(vector<pair<string,string>>());
        } lista_parametros ')' {
            abrirFuncao("void", "void", $2.label);
        } Bloco {
            $$.tipo = fecharFuncao($2.label, $8.traducao);
            $$.label = "";
            $$.traducao = "";
        } ;

declaracao : tipo TK_ID ';' {
    string varLabel = gentempcode(); 
    declararVariavel($2.label, $1.tipo, varLabel);
    vars_temporarias += "\t" + $1.label + " " + varLabel + ";\n"; 
    $$.traducao = "";
} | tipo TK_ID TK_ATRIB E ';' {
    if ($4.tipo == "void") erroSemantico("Nao e possivel atribuir o resultado de uma funcao 'void' a uma variavel.");
    string varLabel = gentempcode(); 
    declararVariavel($2.label, $1.tipo, varLabel);
    vars_temporarias += "\t" + $1.label + " " + varLabel + ";\n";
    string trad = $4.traducao; string lab = $4.label;
    if ($1.tipo == "float" && $4.tipo == "int") { Cast c = gerarCast($4.label, "int", "float"); trad += c.traducao; lab = c.label; }
    if ($1.tipo == "int" && $4.tipo == "float") erroSemantico("Nao e possivel atribuir float a int sem cast explicito. Use (int).");
    $$.traducao = trad + "\t" + varLabel + " = " + lab + ";\n";
} | TK_TIPO_STRING TK_ID ';' {
    string varLabel = gentempcode();
    string capLabel = varLabel + "_cap";
    declararVariavel($2.label, "string", varLabel);
    vars_temporarias += "\tint " + capLabel + ";\n";
    vars_temporarias += "\tchar *" + varLabel + ";\n";
    $$.traducao = "\t" + capLabel + " = 1000;\n"
                + "\t" + varLabel + " = (char *) malloc(" + capLabel + ");\n"
                + "\t" + varLabel + "[0] = '\\0';\n";
} | TK_TIPO_STRING TK_ID TK_ATRIB TK_STR_LITERAL ';' {
    string varLabel = gentempcode();
    string capLabel = varLabel + "_cap";
    declararVariavel($2.label, "string", varLabel);
    vars_temporarias += "\tint " + capLabel + ";\n";
    vars_temporarias += "\tchar *" + varLabel + ";\n";
    $$.traducao = "\t" + capLabel + " = 1000;\n"
                + "\t" + varLabel + " = (char *) malloc(" + capLabel + ");\n"
                + "\t" + varLabel + "[0] = '\\0';\n"
                + "\t_miku_strcpy_safe(&" + varLabel + ", &" + capLabel + ", " + $4.label + ");\n";
}
/* Declaracao Vetor 1D */
| tipo TK_ID '[' E ']' ';' {
    if ($4.tipo != "int") erroSemantico("Tamanho do vetor deve ser inteiro.");
    string varLabel = gentempcode();
    declararVariavelArray($2.label, $1.tipo, varLabel, 1, "");
    vars_temporarias += "\t" + $1.tipo + "* " + varLabel + ";\n";
    $$.traducao = $4.traducao + "\t" + varLabel + " = (" + $1.tipo + "*) malloc(" + $4.label + " * sizeof(" + $1.tipo + "));\n";
}
/* Declaracao Matriz 2D */
| tipo TK_ID '[' E ']' '[' E ']' ';'
{
    if ($4.tipo != "int" || $7.tipo != "int") {
        erroSemantico("Tamanhos da matriz devem ser inteiros.");
    }
    
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
};

atrib_base : TK_ID TK_ATRIB E {
    Variavel* v = buscarVariavel($1.label);
    if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    if (v->is_array != 0) erroSemantico("Uso incorreto de vetor/matriz. Especifique os indices.");
    if ($3.tipo == "void") erroSemantico("Nao e possivel atribuir o resultado de uma funcao 'void' a uma variavel.");
    string trad = $3.traducao; string lab = $3.label;
    if (v->tipo == "string") {
        $$.traducao = trad + "\t_miku_strcpy_safe(&" + v->label + ", &" + v->label + "_cap, " + lab + ");\n";
    } else {
        if (v->tipo == "float" && $3.tipo == "int") { Cast c = gerarCast($3.label, "int", "float"); trad += c.traducao; lab = c.label; }
        if (v->tipo == "int" && $3.tipo == "float") erroSemantico("Nao e possivel atribuir float a int sem cast explicito. Use (int).");
        $$.traducao = trad + "\t" + v->label + " = " + lab + ";\n";
    }
}
| TK_ID TK_MAIS_IGUAL E { $$.traducao = gerarAtribuicaoComposta($1.label, "+", $3); }
| TK_ID TK_MENOS_IGUAL E { $$.traducao = gerarAtribuicaoComposta($1.label, "-", $3); }
| TK_ID TK_VEZES_IGUAL E { $$.traducao = gerarAtribuicaoComposta($1.label, "*", $3); }
| TK_ID TK_DIV_IGUAL E { $$.traducao = gerarAtribuicaoComposta($1.label, "/", $3); }

/* Atribuicao para Vetores 1D */
| TK_ID '[' E ']' TK_ATRIB E {
    if ($3.tipo != "int") erroSemantico("Indice do vetor deve ser inteiro.");
    Variavel* v = buscarVariavel($1.label);
    if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    if (v->is_array != 1) erroSemantico("Variavel '" + $1.label + "' nao eh vetor.");
    if ($6.tipo == "void") erroSemantico("Nao e possivel atribuir o resultado de uma funcao 'void' a uma variavel.");
    string trad = $3.traducao + $6.traducao; string lab = $6.label;
    if (v->tipo == "float" && $6.tipo == "int") { Cast c = gerarCast($6.label, "int", "float"); trad += c.traducao; lab = c.label; }
    if (v->tipo == "int" && $6.tipo == "float") erroSemantico("Nao e possivel atribuir float a int sem cast explicito. Use (int).");
    $$.traducao = trad + "\t" + v->label + "[" + $3.label + "] = " + lab + ";\n";
}
| TK_ID '[' E ']' TK_MAIS_IGUAL E  { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "+", $3, nullptr, $6); }
| TK_ID '[' E ']' TK_MENOS_IGUAL E { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "-", $3, nullptr, $6); }
| TK_ID '[' E ']' TK_VEZES_IGUAL E { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "*", $3, nullptr, $6); }
| TK_ID '[' E ']' TK_DIV_IGUAL E   { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "/", $3, nullptr, $6); }

/* Atribuicao para Matrizes 2D */
| TK_ID '[' E ']' '[' E ']' TK_ATRIB E {
    if ($3.tipo != "int" || $6.tipo != "int") erroSemantico("Indices da matriz devem ser inteiros.");
    Variavel* v = buscarVariavel($1.label);
    if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    if (v->is_array != 2) erroSemantico("Variavel '" + $1.label + "' nao eh matriz.");
    if ($9.tipo == "void") erroSemantico("Nao e possivel atribuir o resultado de uma funcao 'void' a uma variavel.");
    string trad = $3.traducao + $6.traducao + $9.traducao; string lab = $9.label;
    if (v->tipo == "float" && $9.tipo == "int") { Cast c = gerarCast($9.label, "int", "float"); trad += c.traducao; lab = c.label; }
    string calcIndex = gentempcode();
    vars_temporarias += "\tint " + calcIndex + ";\n";
    trad += "\t" + calcIndex + " = " + $3.label + " * " + v->col_size + " + " + $6.label + ";\n";
    $$.traducao = trad + "\t" + v->label + "[" + calcIndex + "] = " + lab + ";\n";
}
| TK_ID '[' E ']' '[' E ']' TK_MAIS_IGUAL E  { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "+", $3, &$6, $9); }
| TK_ID '[' E ']' '[' E ']' TK_MENOS_IGUAL E { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "-", $3, &$6, $9); }
| TK_ID '[' E ']' '[' E ']' TK_VEZES_IGUAL E { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "*", $3, &$6, $9); }
| TK_ID '[' E ']' '[' E ']' TK_DIV_IGUAL E   { $$.traducao = gerarAtribuicaoCompostaArray($1.label, "/", $3, &$6, $9); };

atribuicao : atrib_base ';' { $$.traducao = $1.traducao; };

E : E '+' E {
      // 1. Determina o tipo resultante da operação através da tabela semântica
      string tipo_res = tipoResultante($1.tipo, $3.tipo);
      if (tipo_res == "erro") {
          erroSemantico("Operacao de soma (+) invalida entre os tipos: " + $1.tipo + " e " + $3.tipo);
      }

      // 2. Propaga o tipo correto para o nó atual da árvore
      $$.tipo = tipo_res;
      $$.label = gentempcode();
      vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

      // Variables auxiliares para não perder o estado original
      string trad1 = $1.traducao;
      string lab1 = $1.label;
      string trad3 = $3.traducao;
      string lab3 = $3.label;

      // 3. Aplica a coerção (cast) implícita se houver mistura de tipos
      if ($1.tipo == "int" && $3.tipo == "float") {
          Cast c = gerarCast($1.label, "int", "float");
          trad1 += c.traducao;
          lab1 = c.label;
      } else if ($1.tipo == "float" && $3.tipo == "int") {
          Cast c = gerarCast($3.label, "int", "float");
          trad3 += c.traducao;
          lab3 = c.label;
      }

      // 4. Junta tudo na tradução final com os labels atualizados
      $$.traducao = trad1 + trad3 + "\t" + $$.label + " = " + lab1 + " + " + lab3 + ";\n";
  }

  | E '-' E {
      string tipo_res = tipoResultante($1.tipo, $3.tipo);
      if (tipo_res == "erro") {
          erroSemantico("Operacao de subtracao (-) invalida entre os tipos: " + $1.tipo + " e " + $3.tipo);
      }

      $$.tipo = tipo_res;
      $$.label = gentempcode();
      vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

      string trad1 = $1.traducao;
      string lab1 = $1.label;
      string trad3 = $3.traducao;
      string lab3 = $3.label;

      if ($1.tipo == "int" && $3.tipo == "float") {
          Cast c = gerarCast($1.label, "int", "float");
          trad1 += c.traducao;
          lab1 = c.label;
      } else if ($1.tipo == "float" && $3.tipo == "int") {
          Cast c = gerarCast($3.label, "int", "float");
          trad3 += c.traducao;
          lab3 = c.label;
      }

      $$.traducao = trad1 + trad3 + "\t" + $$.label + " = " + lab1 + " - " + lab3 + ";\n";
  }

  | E '*' E {
      string tipo_res = tipoResultante($1.tipo, $3.tipo);
      if (tipo_res == "erro") {
          erroSemantico("Operacao de multiplicacao (*) invalida entre os tipos: " + $1.tipo + " e " + $3.tipo);
      }

      $$.tipo = tipo_res;
      $$.label = gentempcode();
      vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

      string trad1 = $1.traducao;
      string lab1 = $1.label;
      string trad3 = $3.traducao;
      string lab3 = $3.label;

      if ($1.tipo == "int" && $3.tipo == "float") {
          Cast c = gerarCast($1.label, "int", "float");
          trad1 += c.traducao;
          lab1 = c.label;
      } else if ($1.tipo == "float" && $3.tipo == "int") {
          Cast c = gerarCast($3.label, "int", "float");
          trad3 += c.traducao;
          lab3 = c.label;
      }

      $$.traducao = trad1 + trad3 + "\t" + $$.label + " = " + lab1 + " * " + lab3 + ";\n";
  }

  | E '/' E {
      string tipo_res = tipoResultante($1.tipo, $3.tipo);
      if (tipo_res == "erro") {
          erroSemantico("Operacao de divisao (/) invalida entre os tipos: " + $1.tipo + " e " + $3.tipo);
      }

      $$.tipo = tipo_res;
      $$.label = gentempcode();
      vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

      string trad1 = $1.traducao;
      string lab1 = $1.label;
      string trad3 = $3.traducao;
      string lab3 = $3.label;

      if ($1.tipo == "int" && $3.tipo == "float") {
          Cast c = gerarCast($1.label, "int", "float");
          trad1 += c.traducao;
          lab1 = c.label;
      } else if ($1.tipo == "float" && $3.tipo == "int") {
          Cast c = gerarCast($3.label, "int", "float");
          trad3 += c.traducao;
          lab3 = c.label;
      }

      $$.traducao = trad1 + trad3 + "\t" + $$.label + " = " + lab1 + " / " + lab3 + ";\n";
  }
  | E TK_E E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " && " + $3.label + ";\n"; }
  | E TK_OU E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " || " + $3.label + ";\n"; }
  | TK_NAO E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $2.traducao + "\t" + $$.label + " = !" + $2.label + ";\n"; }
  | '-' E %prec UMINUS { 
      if ($2.tipo != "int" && $2.tipo != "float") {
          erroSemantico("Operador unario '-' nao suportado para o tipo " + $2.tipo);
      }
      $$.label = gentempcode(); 
      vars_temporarias += "\t" + $2.tipo + " " + $$.label + ";\n";
      $$.tipo = $2.tipo; // Aqui você já propagava corretamente!
      $$.traducao = $2.traducao + "\t" + $$.label + " = -" + $2.label + ";\n";
  }
  | '+' E %prec UPLUS { 
      if ($2.tipo != "int" && $2.tipo != "float") {
          erroSemantico("Operador unario '+' nao suportado para o tipo " + $2.tipo);
      }
      $$.label = $2.label; $$.tipo = $2.tipo; $$.traducao = $2.traducao; }
  | E TK_IGUAL E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " == " + $3.label + ";\n"; }
  | E TK_DIFERENTE E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " != " + $3.label + ";\n"; }
  | E '<' E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " < " + $3.label + ";\n"; }
  | E '>' E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " > " + $3.label + ";\n"; }
  | E TK_MENOR_IGUAL E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " <= " + $3.label + ";\n"; }
  | E TK_MAIOR_IGUAL E { $$.tipo = "bool"; $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " >= " + $3.label + ";\n"; }
  | '(' E ')' { $$.label = $2.label; $$.tipo = $2.tipo; $$.traducao = $2.traducao; }
  | '(' tipo ')' E %prec CAST { $$.label = gentempcode(); $$.tipo = $2.tipo; vars_temporarias += "\t" + $2.label + " " + $$.label + ";\n"; $$.traducao = $4.traducao + "\t" + $$.label + " = (" + $2.label + ") " + $4.label + ";\n"; }
  | TK_NUM { if ($1.tipo == "char") { $$.label = $1.label; $$.tipo = $1.tipo; $$.traducao = ""; } else { $$.label = gentempcode(); $$.tipo = $1.tipo; vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n"; } }
  | TK_TRUE { $$.label = "1"; $$.tipo = "bool"; $$.traducao = ""; }
  | TK_FALSE { $$.label = "0"; $$.tipo = "bool"; $$.traducao = ""; }
  | TK_ID { 
      Variavel* v = buscarVariavel($1.label); 
      if(v) { 
          if(v->is_array != 0) erroSemantico("Variavel '" + $1.label + "' eh um vetor/matriz, especifique o indice.");
          $$.label = v->label; $$.tipo = v->tipo; $$.traducao = ""; 
      } else { erroSemantico("Variavel '" + $1.label + "' nao declarada."); }
  }
  /* Leitura Vetor 1D em Expressões (ex: x = a[i] + 5) */
  | TK_ID '[' E ']' {
      if ($3.tipo != "int") erroSemantico("Indice do vetor deve ser inteiro.");
      Variavel* v = buscarVariavel($1.label);
      if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
      if (v->is_array != 1) erroSemantico("Variavel '" + $1.label + "' nao eh vetor.");
      $$.label = gentempcode();
      vars_temporarias += "\t" + v->tipo + " " + $$.label + ";\n";
      $$.tipo = v->tipo;
      $$.traducao = $3.traducao + "\t" + $$.label + " = " + v->label + "[" + $3.label + "];\n";
  }
  /* Leitura Matriz 2D em Expressões */
  | TK_ID '[' E ']' '[' E ']' {
      if ($3.tipo != "int" || $6.tipo != "int") erroSemantico("Indices da matriz devem ser inteiros.");
      Variavel* v = buscarVariavel($1.label);
      if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
      if (v->is_array != 2) erroSemantico("Variavel '" + $1.label + "' nao eh matriz.");
      string calcIndex = gentempcode();
      vars_temporarias += "\tint " + calcIndex + ";\n";
      string indexCode = "\t" + calcIndex + " = " + $3.label + " * " + v->col_size + " + " + $6.label + ";\n";
      $$.label = gentempcode();
      vars_temporarias += "\t" + v->tipo + " " + $$.label + ";\n";
      $$.tipo = v->tipo;
      $$.traducao = $3.traducao + $6.traducao + indexCode + "\t" + $$.label + " = " + v->label + "[" + calcIndex + "];\n";
  }
  /* Chamada de funcao usada como expressao (ex: x = soma(1, 2) + 3) */
  | TK_ID '(' {
      pilhaArgsReais.push(vector<atributos>());
  } lista_argumentos ')' {
      vector<atributos> argumentos = pilhaArgsReais.top();
      pilhaArgsReais.pop();
      atributos r = gerarChamadaFuncao($1.label, argumentos);
      $$.label = r.label;
      $$.tipo = r.tipo;
      $$.traducao = r.traducao;
  }
  | TK_STR_LITERAL { $$.label = $1.label; $$.tipo = "string"; $$.traducao = ""; }
  /* Operador de resto (%)*/
  | E TK_MOD E {
    if ($1.tipo != "int" || $3.tipo != "int") erroSemantico("Operador '%' requer operandos inteiros.");
    $$.label = gentempcode();
    $$.tipo = "int";
    vars_temporarias += "\tint " + $$.label + ";\n";
    $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " % " + $3.label + ";\n";
    }
    /* Operador de potência (**) */
    | E TK_POW E {
    $$.tipo = tipoResultante($1.tipo, $3.tipo);
    if ($$.tipo == "erro") erroSemantico("Tipos incompativeis para operador '**'.");
    $$.label = gentempcode();
    vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
    string base = $1.label;
    string exp  = $3.label;
    string trad = $1.traducao + $3.traducao;
    if ($$.tipo == "float") {
        if ($1.tipo == "int") { Cast c = gerarCast($1.label, "int", "float"); trad += c.traducao; base = c.label; }
        if ($3.tipo == "int") { Cast c = gerarCast($3.label, "int", "float"); trad += c.traducao; exp  = c.label; }
        string i_f     = gentempcode();
        string res_f   = gentempcode();
        string Lloop_f = genlabel();
        string Lend_f  = genlabel();
        vars_temporarias += "\tint "   + i_f   + ";\n";
        vars_temporarias += "\tfloat " + res_f + ";\n";
        trad += "\t" + res_f + " = 1.0;\n";
        trad += "\t" + i_f   + " = 0;\n";
        trad += Lloop_f + ":;\n";
        trad += "\tif (" + i_f + " >= " + exp + ") goto " + Lend_f + ";\n";
        trad += "\t" + res_f + " = " + res_f + " * " + base + ";\n";
        trad += "\t" + i_f   + " = " + i_f   + " + 1;\n";
        trad += "\tgoto " + Lloop_f + ";\n";
        trad += Lend_f + ":;\n";
        $$.label = res_f;
    } else {
        string i     = gentempcode();
        string res   = gentempcode();
        string Lloop = genlabel();
        string Lend  = genlabel();
        vars_temporarias += "\tint " + i   + ";\n";
        vars_temporarias += "\tint " + res + ";\n";
        trad += "\t" + res + " = 1;\n";
        trad += "\t" + i   + " = 0;\n";
        trad += Lloop + ":;\n";
        trad += "\tif (" + i + " >= " + exp + ") goto " + Lend + ";\n";
        trad += "\t" + res + " = " + res + " * " + base + ";\n";
        trad += "\t" + i   + " = " + i   + " + 1;\n";
        trad += "\tgoto " + Lloop + ";\n";
        trad += Lend + ":;\n";
        $$.label = res;
    }
    $$.traducao = trad;
}
  ;

%%

string gentempcode() { var_temp_qnt++; return "t" + to_string(var_temp_qnt); }

int main(int argc, char* argv[]) {
    var_temp_qnt = 0;
    entrarEscopo();
    if (argc > 1) { yyin = fopen(argv[1], "r"); }
    if (yyparse() == 0) cout << codigo_gerado;
    sairEscopo();
    return 0;
}

void yyerror(string MSG) { cerr << "Erro Sintatico na linha " << linha << ": " << MSG << endl; }