%{
#include <iostream>
#include <string>
#include <stdio.h>
#include <map>
#include <stack>
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

void declararVariavel(string nome, string tipo, string label) { 
    pilhaEscopos.top()[nome] = {tipo, label, 0, ""}; 
}

void declararVariavelArray(string nome, string tipo, string label, int is_array, string col_size) {
    pilhaEscopos.top()[nome] = {tipo, label, is_array, col_size};
}

Variavel* buscarVariavel(string nome) {
    auto copia = pilhaEscopos;
    while (!copia.empty()) {
        if (copia.top().count(nome)) return &copia.top()[nome];
        copia.pop();
    }
    return nullptr;
}

string tipoResultante(string t1, string t2) {
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

string gerarAtribuicaoComposta(string idLabel, string op, atributos exp) {
    Variavel* v = buscarVariavel(idLabel);
    if (!v) erroSemantico("Variavel '" + idLabel + "' nao declarada.");
    if (v->tipo == "string") erroSemantico("Operadores compostos nao suportados para strings.");

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
%token TK_TIPO_STRING TK_STR_LITERAL
%token TK_MAIS_IGUAL TK_MENOS_IGUAL TK_VEZES_IGUAL TK_DIV_IGUAL

%nonassoc LOWER_THAN_ELSE
%nonassoc TK_ELSE

%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/'
%right TK_NAO UMINUS UPLUS
%right CAST

%start S

%%

S : lista_comandos {
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
    "\nint main(void) {\n" + vars_temporarias + "\n" + $1.traducao + "\treturn 0;\n}\n";
} ;

lista_comandos : lista_comandos comando { $$.traducao = $1.traducao + $2.traducao; }
               |                        { $$.traducao = ""; } ;

comando : declaracao             { $$.traducao = $1.traducao; }
        | atribuicao             { $$.traducao = $1.traducao; }
        | E ';'                  { $$.traducao = $1.traducao; }
        | Bloco                  { $$.traducao = $1.traducao; }
        | TK_PRINT '(' E ')' ';' {
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
            if (stack_break.empty()) erroSemantico("comando 'break' fora de um laco de repeticao.");
            $$.traducao = "\tgoto " + stack_break.top() + ";\n";
        }
        | TK_CONTINUE ';' {
            if (stack_continue.empty()) erroSemantico("comando 'continue' fora de um laco de repeticao.");
            $$.traducao = "\tgoto " + stack_continue.top() + ";\n";
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

declaracao : tipo TK_ID ';' {
    string varLabel = gentempcode(); 
    declararVariavel($2.label, $1.tipo, varLabel);
    vars_temporarias += "\t" + $1.label + " " + varLabel + ";\n"; 
    $$.traducao = "";
} | tipo TK_ID TK_ATRIB E ';' {
    string varLabel = gentempcode(); 
    declararVariavel($2.label, $1.tipo, varLabel);
    vars_temporarias += "\t" + $1.label + " " + varLabel + ";\n";
    string trad = $4.traducao; string lab = $4.label;
    if ($1.tipo == "float" && $4.tipo == "int") { Cast c = gerarCast($4.label, "int", "float"); trad += c.traducao; lab = c.label; }
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
| tipo TK_ID '[' E ']' '[' E ']' ';' {
    if ($4.tipo != "int" || $6.tipo != "int") erroSemantico("Tamanhos da matriz devem ser inteiros.");
    string varLabel = gentempcode();
    string colSize = gentempcode();
    vars_temporarias += "\tint " + colSize + ";\n";
    string trad = $4.traducao + $6.traducao + "\t" + colSize + " = " + $6.label + ";\n";
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
    string trad = $3.traducao; string lab = $3.label;
    if (v->tipo == "string") {
        $$.traducao = trad + "\t_miku_strcpy_safe(&" + v->label + ", &" + v->label + "_cap, " + lab + ");\n";
    } else {
        if (v->tipo == "float" && $3.tipo == "int") { Cast c = gerarCast($3.label, "int", "float"); trad += c.traducao; lab = c.label; }
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
    string trad = $3.traducao + $6.traducao; string lab = $6.label;
    if (v->tipo == "float" && $6.tipo == "int") { Cast c = gerarCast($6.label, "int", "float"); trad += c.traducao; lab = c.label; }
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
  | E TK_E E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " && " + $3.label + ";\n"; }
  | E TK_OU E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " || " + $3.label + ";\n"; }
  | TK_NAO E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $2.traducao + "\t" + $$.label + " = !" + $2.label + ";\n"; }
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
  | E TK_IGUAL E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " == " + $3.label + ";\n"; }
  | E TK_DIFERENTE E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " != " + $3.label + ";\n"; }
  | E '<' E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " < " + $3.label + ";\n"; }
  | E '>' E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " > " + $3.label + ";\n"; }
  | E TK_MENOR_IGUAL E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " <= " + $3.label + ";\n"; }
  | E TK_MAIOR_IGUAL E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " >= " + $3.label + ";\n"; }
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
  | TK_STR_LITERAL { $$.label = $1.label; $$.tipo = "string"; $$.traducao = ""; }
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