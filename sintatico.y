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
};

stack<map<string, Variavel>> pilhaEscopos;

void entrarEscopo() { pilhaEscopos.push(map<string, Variavel>()); }
void sairEscopo() { pilhaEscopos.pop(); }
void declararVariavel(string nome, string tipo, string label) { pilhaEscopos.top()[nome] = {tipo, label}; }

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

/* Precedência para resolver o Dangling Else */
%nonassoc LOWER_THAN_ELSE
%nonassoc TK_ELSE

%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/'
%right TK_NAO

%start S

%%

S : lista_comandos {
    codigo_gerado = "/*__________________________\n\n★  MIKU COMPILER (^_^)  ★\n__________________________*/\n\n#include <stdio.h>\nint main(void) {\n" + vars_temporarias + "\n" + $1.traducao + "\treturn 0;\n}\n";
} ;

lista_comandos : lista_comandos comando { $$.traducao = $1.traducao + $2.traducao; }
               |                        { $$.traducao = ""; } ;

comando : declaracao             { $$.traducao = $1.traducao; }
        | atribuicao             { $$.traducao = $1.traducao; }
        | E ';'                  { $$.traducao = $1.traducao; }
        | Bloco                  { $$.traducao = $1.traducao; }
        | TK_PRINT '(' E ')' ';' { 
            string fmt = ($3.tipo == "float") ? "%f" : "%d";
            $$.traducao = $3.traducao + "\tprintf(\"" + fmt + "\\n\", " + $3.label + ");\n"; 
        }
        | TK_READ '(' TK_ID ')' ';' { 
            Variavel* v = buscarVariavel($3.label);
            string fmt = (v->tipo == "float") ? "%f" : "%d";
            $$.traducao = "\tscanf(\"" + fmt + "\", &" + v->label + ");\n";
        }
        | TK_BREAK ';' {
            if (stack_break.empty()) erroSemantico("comando 'break' fora de um laco de repeticao.");
            $$.traducao = "\tgoto " + stack_break.top() + ";\n";
        }
        | TK_CONTINUE ';' {
            if (stack_continue.empty()) erroSemantico("comando 'continue' fora de um laco de repeticao.");
            $$.traducao = "\tgoto " + stack_continue.top() + ";\n";
        }
        /* Fluxo de Controle com Precedência */
        | TK_IF '(' E ')' Bloco %prec LOWER_THAN_ELSE {
            string l1 = genlabel();
            $$.traducao = $3.traducao + "\tif (!" + $3.label + ") goto " + l1 + ";\n" + $5.traducao + l1 + ":;\n";
        }
        | TK_IF '(' E ')' Bloco TK_ELSE Bloco {
            string l1 = genlabel(); string l2 = genlabel();
            $$.traducao = $3.traducao + "\tif (!" + $3.label + ") goto " + l1 + ";\n" + $5.traducao + "\tgoto " + l2 + ";\n" + l1 + ":;\n" + $7.traducao + l2 + ":;\n";
        }
        | TK_WHILE '(' E ')' {
            // Ação de meio de regra ($5)
            $$.label = genlabel();    // label de inicio (alvo do continue)
            $$.traducao = genlabel(); // label de fim (alvo do break)
            
            stack_continue.push($$.label);
            stack_break.push($$.traducao);
        } Bloco {
            // Ação final ($7)
            string start = $5.label;
            string end = $5.traducao;
            
            $$.traducao = start + ":;\n" + 
                          $3.traducao + 
                          "\tif (!" + $3.label + ") goto " + end + ";\n" + 
                          $6.traducao + 
                          "\tgoto " + start + ";\n" + 
                          end + ":;\n";
                          
            stack_continue.pop();
            stack_break.pop();
        }
        | TK_DO {
            // Ação de meio de regra ($2)
            $$.label = genlabel();    // start (inicio do bloco)
            $$.traducao = genlabel(); // cont (alvo do continue, antes da condicao)
            $$.tipo = genlabel();     // end (alvo do break)
            
            stack_continue.push($$.traducao);
            stack_break.push($$.tipo);
        } Bloco TK_WHILE '(' E ')' ';' {
            string start = $2.label;
            string cont = $2.traducao;
            string end = $2.tipo;
            
            $$.traducao = start + ":;\n" + 
                          $3.traducao + 
                          cont + ":;\n" + 
                          $6.traducao + 
                          "\tif (" + $6.label + ") goto " + start + ";\n" +
                          end + ":;\n";
                          
            stack_continue.pop();
            stack_break.pop();
        }
        | TK_FOR '(' atrib_base ';' E ';' {
            // Ação de meio de regra ($7)
            $$.label = genlabel();    // start (avaliacao da condicao)
            $$.traducao = genlabel(); // end (alvo do break)
            $$.tipo = genlabel();     // inc (alvo do continue, no incremento)
            
            stack_continue.push($$.tipo);
            stack_break.push($$.traducao);
        } atrib_base ')' Bloco {
            string start = $7.label;
            string end = $7.traducao;
            string inc = $7.tipo;
            
            $$.traducao = $3.traducao + 
                          start + ":;\n" + 
                          $5.traducao + 
                          "\tif (!" + $5.label + ") goto " + end + ";\n" + 
                          $10.traducao + 
                          inc + ":;\n" + 
                          $8.traducao + 
                          "\tgoto " + start + ";\n" + 
                          end + ":;\n";
                          
            stack_continue.pop();
            stack_break.pop();
        }
        | TK_SWITCH '(' E ')' {
            // Ação de meio de regra
            string flag = gentempcode();
            vars_temporarias += "\tint " + flag + " = 0;\n"; // Inicializa a flag a 0
            
            stack_switch_expr.push($3.label);
            stack_switch_flag.push(flag);
            
            $$.label = genlabel(); // Label de fim (para o break saber para onde saltar)
            stack_break.push($$.label);
        } '{' casos '}' {
            // Ação final
            $$.traducao = $3.traducao + $7.traducao + $5.label + ":;\n";
            
            stack_switch_expr.pop();
            stack_switch_flag.pop();
            stack_break.pop();
        };

Bloco : '{' { entrarEscopo(); } lista_comandos '}' { $$.traducao = "\t{\n" + $3.traducao + "\t}\n"; sairEscopo(); };

casos : casos caso { $$.traducao = $1.traducao + $2.traducao; }
      | /* vazio */ { $$.traducao = ""; }
      ;

caso : TK_CASE TK_NUM ':' lista_comandos {
    string expr = stack_switch_expr.top();
    string flag = stack_switch_flag.top();
    string next_case = genlabel();

    $$.traducao = "\tif (" + expr + " == " + $2.label + ") " + flag + " = 1;\n" +
                  "\tif (!" + flag + ") goto " + next_case + ";\n" +
                  $4.traducao +
                  next_case + ":;\n";
}
| TK_DEFAULT ':' lista_comandos {
    string flag = stack_switch_flag.top();
    string next_case = genlabel();

    $$.traducao = "\t" + flag + " = 1;\n" +
                  "\tif (!" + flag + ") goto " + next_case + ";\n" +
                  $3.traducao +
                  next_case + ":;\n";
}
;

tipo : TK_TIPO_INT   { $$.tipo = "int";   $$.label = "int"; }
     | TK_TIPO_FLOAT { $$.tipo = "float"; $$.label = "float"; }
     | TK_TIPO_BOOL  { $$.tipo = "bool";  $$.label = "int"; }
     | TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; } 
     | TK_TIPO_STRING { $$.tipo = "string"; $$.label = "char*"; };

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
};

atrib_base : TK_ID TK_ATRIB E {
    Variavel* v = buscarVariavel($1.label);
    if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
    string trad = $3.traducao; string lab = $3.label;
    if (v->tipo == "float" && $3.tipo == "int") { Cast c = gerarCast($3.label, "int", "float"); trad += c.traducao; lab = c.label; }
    $$.traducao = trad + "\t" + v->label + " = " + lab + ";\n";
};

atribuicao : atrib_base ';' { $$.traducao = $1.traducao; };

E : E '+' E { $$.label = gentempcode(); vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " + " + $3.label + ";\n"; }
  | E '-' E { $$.label = gentempcode(); vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " - " + $3.label + ";\n"; }
  | E '*' E { $$.label = gentempcode(); vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " * " + $3.label + ";\n"; }
  | E '/' E { $$.label = gentempcode(); vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " / " + $3.label + ";\n"; }
  | E TK_E E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " && " + $3.label + ";\n"; }
  | E TK_OU E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " || " + $3.label + ";\n"; }
  | TK_NAO E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $2.traducao + "\t" + $$.label + " = !" + $2.label + ";\n"; }
  | E TK_IGUAL E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " == " + $3.label + ";\n"; }
  | E TK_DIFERENTE E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " != " + $3.label + ";\n"; }
  | E '<' E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " < " + $3.label + ";\n"; }
  | E '>' E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " > " + $3.label + ";\n"; }
  | E TK_MENOR_IGUAL E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " <= " + $3.label + ";\n"; }
  | E TK_MAIOR_IGUAL E { $$.label = gentempcode(); vars_temporarias += "\tint " + $$.label + ";\n"; $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " >= " + $3.label + ";\n"; }
  | '(' E ')' { $$.label = $2.label; $$.tipo = $2.tipo; $$.traducao = $2.traducao; }
  | '(' tipo ')' E { $$.label = gentempcode(); $$.tipo = $2.tipo; vars_temporarias += "\t" + $2.label + " " + $$.label + ";\n"; $$.traducao = $4.traducao + "\t" + $$.label + " = (" + $2.label + ") " + $4.label + ";\n"; }
  | TK_NUM { if ($1.tipo == "char") { $$.label = $1.label; $$.tipo = $1.tipo; $$.traducao = ""; } else { $$.label = gentempcode(); $$.tipo = $1.tipo; vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n"; } }
  | TK_TRUE { $$.label = "1"; $$.tipo = "bool"; $$.traducao = ""; }
  | TK_FALSE { $$.label = "0"; $$.tipo = "bool"; $$.traducao = ""; }
  | TK_ID { Variavel* v = buscarVariavel($1.label); if(v) { $$.label = v->label; $$.tipo = v->tipo; $$.traducao = ""; } else { erroSemantico("Variavel '" + $1.label + "' nao declarada."); } }
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