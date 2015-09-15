module ast;

import std.d.lexer, std.d.parser, std.d.ast;
import std.json, std.array, std.conv;
import iz.enumset, iz.memory;

import common;

private
{
    enum AstInfos {ModuleName, ErrorsJson, ErrorsPas, SymsJson, SymsPas}
    alias CachedInfos = EnumSet!(AstInfos, Set8);

    enum SymbolType
    {
        _alias,
        _class,
        _enum,
        _error,
        _function,
        _interface,
        _import,
        _mixin,   // (template decl)
        _struct,
        _template,
        _union,
        _variable,
        _warning
    }

    struct Symbol
    {
        size_t line;
        size_t col;
        string name;
        SymbolType type;
        Symbol * [] subs;

        ~this()
        {
            foreach_reverse(i; 0 .. subs.length)
                subs[i].destruct;
        }

        void serializePas(ref Appender!string lfmApp)
        {
            lfmApp.put("\ritem\r");

            lfmApp.put(format("line = %d\r", line));
            lfmApp.put(format("col = %d\r", col));
            lfmApp.put(format("name = '%s'\r", name));
            lfmApp.put(format("symType = %s\r", type));

            lfmApp.put("subs = <");
            if (subs.length) foreach(Symbol * sub; subs)
                sub.serializePas(lfmApp);
            lfmApp.put(">\r");
            lfmApp.put("end");
        }

        void serializeJson(ref JSONValue json)
        {
            auto vobj = parseJSON("{}");
            vobj["line"]= JSONValue(line);
            vobj["col"] = JSONValue(col);
            vobj["name"]= JSONValue(name);
            vobj["type"]= JSONValue(to!string(type));
            if (subs.length)
            {
                auto vsubs = parseJSON("[]");
                foreach(Symbol * sub; subs)
                    sub.serializeJson(vsubs);
                vobj["items"] = vsubs;
            }
            json.array ~= vobj;
        }
    }

    struct AstError
    {
        size_t line, col;
        string msg;
        bool isErr;
    }

    class SymbolListBuilder : ASTVisitor
    {
        Symbol * root;
        Symbol * parent;

        size_t count;

        alias visit = ASTVisitor.visit;

        this(Module mod)
        {
            root = construct!Symbol;
            resetRoot;
            foreach(Declaration d; mod.declarations)
                visit(d);
        }

        ~this()
        {
            root.destruct;
        }

        final void resetRoot(){parent = root;}

        final string serializePas()
        {
            Appender!string lfmApp;
            lfmApp.reserve(count * 64);

            lfmApp.put("object TSymbolList\rsymbols = <");
            foreach(sym; root.subs) sym.serializePas(lfmApp);
            lfmApp.put(">\rend\r\n");

            return lfmApp.data;
        }

        final JSONValue serializeJson()
        {
            JSONValue result = parseJSON("{}");
            JSONValue vsubs = parseJSON("[]");
            foreach(sym; root.subs) sym.serializeJson(vsubs);
            result["items"] = vsubs;
            return result;
        }

        /// returns a new symbol if the declarator is based on a Token named "name".
        final Symbol * addDeclaration(DT)(DT adt)
        {
            static if
            (
                is(DT == const(EponymousTemplateDeclaration)) ||
                is(DT == const(AnonymousEnumMember))    ||
                is(DT == const(AliasInitializer))       ||
                is(DT == const(ClassDeclaration))       ||
                is(DT == const(Declarator))             ||
                is(DT == const(EnumDeclaration))        ||
                is(DT == const(FunctionDeclaration))    ||
                is(DT == const(InterfaceDeclaration))   ||
                is(DT == const(StructDeclaration))      ||
                is(DT == const(TemplateDeclaration))    ||
                is(DT == const(UnionDeclaration))

            )
            {
                count++;
                auto result = construct!Symbol;
                result.name = adt.name.text;
                result.line = adt.name.line;
                result.col  = adt.name.column;
                parent.subs ~= result;
                return result;
            }

            version(none) assert(0, "addDeclaration no implemented for " ~ DT.stringof);
        }

        /// visitor implementation if the declarator is based on a Token named "name".
        final void namedVisitorImpl(DT, SymbolType st, bool dig = true)(const(DT) dt)
        {
            auto newSymbol = addDeclaration(dt);
            newSymbol.type = st;
            //
            static if (dig)
            {
                auto previousParent = parent;
                scope(exit) parent = previousParent;
                parent = newSymbol;
                dt.accept(this);
            }
        }

        /// visitor implementation for special cases.
        final void otherVisitorImpl(SymbolType st, string name, size_t line, size_t col)
        {
            count++;
            auto result = construct!Symbol;
            result.name = name;
            result.line = line;
            result.col  = col;
            result.type = st;
            parent.subs ~= result;
        }

        final override void visit(const AliasDeclaration decl)
        {
            // why is initializers an array ?
            if (decl.initializers.length > 0)
                namedVisitorImpl!(AliasInitializer, SymbolType._alias)(decl.initializers[0]);
        }

        final override void visit(const AnonymousEnumDeclaration decl)
        {
            if (decl.members.length > 0)
                namedVisitorImpl!(AnonymousEnumMember, SymbolType._enum)(decl.members[0]);
        }

        final override void visit(const ClassDeclaration decl)
        {
            namedVisitorImpl!(ClassDeclaration, SymbolType._class)(decl);
        }

        final override void visit(const Constructor decl)
        {
            otherVisitorImpl(SymbolType._function, "this", decl.line, decl.column);
        }

        final override void visit(const Destructor decl)
        {
            otherVisitorImpl(SymbolType._function, "~this", decl.line, decl.column);
        }

        final override void visit(const EnumDeclaration decl)
        {
            namedVisitorImpl!(EnumDeclaration, SymbolType._enum)(decl);
        }

        final override void visit(const EponymousTemplateDeclaration decl)
        {
            namedVisitorImpl!(EponymousTemplateDeclaration, SymbolType._template)(decl);
        }

        final override void visit(const FunctionDeclaration decl)
        {
            namedVisitorImpl!(FunctionDeclaration, SymbolType._function)(decl);
        }

        final override void visit(const InterfaceDeclaration decl)
        {
            namedVisitorImpl!(InterfaceDeclaration, SymbolType._interface)(decl);
        }

        final override void visit(const ImportDeclaration decl)
        {
            foreach(const(SingleImport) si; decl.singleImports)
            {
                if (!si.identifierChain.identifiers.length)
                    continue;
                //
                string[] modules;
                foreach(ident; si.identifierChain.identifiers)
                {
                    modules ~= ident.text;
                    modules ~= ".";
                }
                //
                otherVisitorImpl(SymbolType._import, modules[0..$-1].join,
                    si.identifierChain.identifiers[0].line,
                    si.identifierChain.identifiers[0].column
                );
            }
        }

        final override void visit(const MixinTemplateDeclaration decl)
        {
            namedVisitorImpl!(TemplateDeclaration, SymbolType._mixin)(decl.templateDeclaration);
        }

        final override void visit(const StructDeclaration decl)
        {
            namedVisitorImpl!(StructDeclaration, SymbolType._struct)(decl);
        }

        final override void visit(const TemplateDeclaration decl)
        {
            namedVisitorImpl!(TemplateDeclaration, SymbolType._template)(decl);
        }

        final override void visit(const UnionDeclaration decl)
        {
            namedVisitorImpl!(UnionDeclaration, SymbolType._union)(decl);
        }

        final override void visit(const VariableDeclaration decl)
        {
            foreach(elem; decl.declarators)
                namedVisitorImpl!(Declarator, SymbolType._variable, false)(elem);
        }

        final override void visit(const StaticConstructor decl)
        {
            otherVisitorImpl(SymbolType._function, "static this", decl.line, decl.column);
        }

        final override void visit(const StaticDestructor decl)
        {
            otherVisitorImpl(SymbolType._function, "static ~this", decl.line, decl.column);
        }
    }
}


struct Ast
{

private:

    ubyte[] src;
    string fname;
    LexerConfig config;
    StringCache strcache;
    Module mod;
    bool scanned;

    CachedInfos cachedInfos;
    string modName;
    ubyte[] jsonErrors;
    ubyte[] pasErrors;
    ubyte[] todosPas;
    ubyte[] todosJson;
    ubyte[] symsPas;
    ubyte[] symsJson;
    static AstError*[] errors;

    final static void parserError(string fname, size_t line, size_t col, string msg, bool isErr)
    {
        errors ~= new AstError(line, col, msg, isErr);
    }

    final void resetCachedInfo()
    {
        cachedInfos = 0;
        modName = modName.init;
        errors = errors.init;
    }

    final void scan()
    {
        resetCachedInfo;
        scanned = false;
        scope(success) scanned = true;

        config = LexerConfig(fname, StringBehavior.source, WhitespaceBehavior.skip);
        mod = parseModule(getTokensForParser(src, config, &strcache), fname, null, &parserError);
    }

public:

    this(string filename)
    {
        fname = filename;
        strcache = StringCache(StringCache.defaultBucketCount);
        rescanFile();
    }

    this(ubyte[] buffer)
    {
        strcache = StringCache(StringCache.defaultBucketCount);
        rescanBuffer(buffer);
    }

    final void rescanFile()
    {
        resetCachedInfo;
        import std.file;
        src = cast(ubyte[]) read(fname, size_t.max);
        scan;
    }

    final void rescanBuffer(ubyte[] buffer)
    {
        resetCachedInfo;
        src = buffer.dup;
        scan;
    }

    final string moduleName()
    {
        string result;

        if (!scanned)
            return result;
        if (AstInfos.ModuleName in cachedInfos)
            return modName;

        cachedInfos += AstInfos.ModuleName;
        if (mod.moduleDeclaration)
        foreach(Token t; mod.moduleDeclaration.moduleName.identifiers)
            result ~= t.text ~ ".";

        if (result.length)
            modName = result[0 .. $-1];
        return modName;
    }

    final ubyte[] todoListPas()
    {
        return null;
    }

    final ubyte[] todoListJson()
    {
        return null;
    }

    final ubyte[] symbolListPas()
    {
        if (AstInfos.SymsPas !in cachedInfos)
        {
            cachedInfos += AstInfos.SymsPas;
            SymbolListBuilder slb = construct!SymbolListBuilder(mod);
            scope(exit) destruct(slb);
            symsPas = cast(ubyte[]) slb.serializePas();
        }
        return symsPas;
    }

    final ubyte[] symbolListJson()
    {
        if (AstInfos.SymsJson !in cachedInfos)
        {
            cachedInfos += AstInfos.SymsJson;
            SymbolListBuilder slb = construct!SymbolListBuilder(mod);
            scope(exit) destruct(slb);
            JSONValue v = slb.serializeJson();
            symsJson = cast(ubyte[]) v.toPrettyString;
        }
        return symsJson;
    }

}
