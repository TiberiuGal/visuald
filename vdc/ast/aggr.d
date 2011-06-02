// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.aggr;

import vdc.util;
import vdc.lexer;
import vdc.semantic;

import vdc.ast.node;
import vdc.ast.mod;
import vdc.ast.tmpl;
import vdc.ast.decl;
import vdc.ast.expr;
import vdc.ast.misc;
import vdc.ast.type;

import std.algorithm;
import std.conv;

//Aggregate:
//    [TemplateParameterList_opt Constraint_opt BaseClass... StructBody]
class Aggregate : Type
{
	mixin ForwardCtor!();
	
	override bool propertyNeedsParens() const { return true; }
	
	bool hasBody = true;
	bool hasTemplArgs;
	bool hasConstraint;
	string ident;

	TemplateParameterList getTemplateParameterList() { return hasTemplArgs ? getMember!TemplateParameterList(0) : null; }
	Constraint getConstraint() { return hasConstraint ? getMember!Constraint(1) : null; }
	StructBody getBody() { return hasBody ? getMember!StructBody(members.length - 1) : null; }

	public /* clone and compare */ { 
	override Aggregate clone()
	{
		Aggregate n = static_cast!Aggregate(super.clone());

		n.hasBody = hasBody;
		n.hasTemplArgs = hasTemplArgs;
		n.hasConstraint = hasConstraint;
		n.ident = ident;
		
		return n;
	}

	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.hasBody == hasBody
			&& tn.hasTemplArgs == hasTemplArgs
			&& tn.hasConstraint == hasConstraint
			&& tn.ident == ident;
	}
	}
	public /* writer */ {
	void bodyToD(CodeWriter writer)
	{
		if(auto bdy = getBody())
		{
			writer.nl;
			writer(getBody());
			writer.nl;
		}
		else
		{
			writer(";");
			writer.nl;
		}
	}
	void tmplToD(CodeWriter writer)
	{
		if(TemplateParameterList tpl = getTemplateParameterList())
			writer(tpl);
		if(auto constraint = getConstraint())
			writer(constraint);
	}
	}
	
	override void _semantic(Scope sc)
	{
		// TODO: TemplateParameterList, Constraint
		if(auto bdy = getBody())
		{
			sc = enterScope(sc);
			bdy.semantic(sc);
			sc = sc.pop();
		}
	}

	override void addSymbols(Scope sc)
	{
		if(ident.length)
			sc.addSymbol(ident, this);
	}
}

class Struct : Aggregate
{
	this() {} // default constructor needed for clone()

	this(ref const(TextSpan) _span)
	{
		super(_span);
	}
	
	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		if(writer.writeReferencedOnly && semanticSearches == 0)
			return;
		
		writer("struct ");
		writer.writeIdentifier(ident);
		tmplToD(writer);
		bodyToD(writer);
	}
	}
}

class Union : Aggregate
{
	this() {} // default constructor needed for clone()

	this(ref const(TextSpan) _span)
	{
		super(_span);
	}
	
	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		if(writer.writeReferencedOnly && semanticSearches == 0)
			return;
		
		writer("union ");
		writer.writeIdentifier(ident);
		tmplToD(writer);
		bodyToD(writer);
	}
	}
}

class InheritingAggregate : Aggregate
{
	mixin ForwardCtor!();
	
	BaseClass[] baseClasses;

	void addBaseClass(BaseClass bc)
	{
		members ~= bc;
		baseClasses ~= bc;
	}
	
	public /* clone and compare */ { 
	override InheritingAggregate clone()
	{
		InheritingAggregate n = static_cast!InheritingAggregate(super.clone());
		
		for(int m = 0; m < members.length; m++)
			if(arrfind(cast(Node[]) baseClasses, members[m]) >= 0)
				n.baseClasses ~= static_cast!BaseClass(n.members[m]);
		
		return n;
	}
	}
	
	override bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
			return true;
		
		if(flags & ConversionFlags.kAllowBaseClass)
			if(auto inh = cast(InheritingAggregate) from)
			{
				foreach(bc; inh.baseClasses)
					if(auto inhbc = bc.getClass())
						if(convertableFrom(inhbc, flags))
							return true;
			}
		return false;
	}
	
	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		// class/interface written by derived class
		writer.writeIdentifier(ident);
		tmplToD(writer);
		if(baseClasses.length)
		{
			if(ident.length > 0)
				writer(" : ");
			writer(baseClasses[0]);
			foreach(bc; baseClasses[1..$])
				writer(", ", bc);
		}
		bodyToD(writer);
	}
	}
}

class Class : InheritingAggregate
{
	this() {} // default constructor needed for clone()

	this(ref const(TextSpan) _span)
	{
		super(_span);
	}
	
	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		if(writer.writeReferencedOnly && semanticSearches == 0)
			return;
		
		writer("class ");
		super.toD(writer);
	}
	}
}

class AnonymousClass : InheritingAggregate
{
	mixin ForwardCtor!();
	
	// "class(args) " written by AnonymousClassType
}

// Interface conflicts with object.Interface
class Intrface : InheritingAggregate
{
	this() {} // default constructor needed for clone()

	this(ref const(TextSpan) _span)
	{
		super(_span);
	}
	
	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		if(writer.writeReferencedOnly && semanticSearches == 0)
			return;
		
		writer(TOK_interface, " ");
		super.toD(writer);
	}
	}
}

// BaseClass:
//    [IdentifierList]
class BaseClass : Node
{
	mixin ForwardCtor!();
	
	this() {} // default constructor needed for clone()
	
	this(TokenId prot, ref const(TextSpan) _span)
	{
		super(prot, _span);
	}

	TokenId getProtection() { return id; }
	IdentifierList getIdentifierList() { return getMember!IdentifierList(0); }
	
	InheritingAggregate getClass()
	{
		auto res = getIdentifierList().resolved;
		if(auto inh = cast(InheritingAggregate) res)
			return inh;
		
		semanticError(text("class or interface expected instead of ", res));
		return null;
	}

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		// do not output protection in anonymous classes, and public is the default anyway
		if(id != TOK_public)
			writer(id, " ");
		writer(getMember(0));
	}

	override void toC(CodeWriter writer)
	{
		writer("public ", getMember(0)); // protection diffent from C
	}
	}
}

// StructBody:
//    [DeclDef...]
class StructBody : Node
{
	mixin ForwardCtor!();
	
	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("{");
		writer.nl();
		{
			auto indent = CodeIndenter(writer);
			foreach(n; members)
				writer(n);
		}
		writer("}");
		writer.nl();
	}
	}
	
	override void addSymbols(Scope sc)
	{
		addMemberSymbols(sc);
	}
}

//Constructor:
//    [TemplateParameters_opt Parameters_opt Constraint_opt FunctionBody]
//    if no parameters: this ( this )
class Constructor : Node
{
	mixin ForwardCtor!();
	
	bool isTemplate() const { return members.length > 2; }
	
	TemplateParameterList getTemplateParameters() { return isTemplate() ? getMember!TemplateParameterList(0) : null; }
	ParameterList getParameters() { return members.length > 1 ? getMember!ParameterList(isTemplate() ? 1 : 0) : null; }
	Constraint getConstraint() { return isTemplate() && members.length > 3 ? getMember!Constraint(2) : null; }
	FunctionBody getBody() { return getMember!FunctionBody(members.length - 1); }
	
	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("this");
		if(auto tpl = getTemplateParameters())
			writer(tpl);
		if(auto pl = getParameters())
			writer(pl);
		else
			writer("(this)");
		if(auto c = getConstraint())
			writer(c);
		
		if(writer.writeImplementations)
		{
			writer.nl;
			writer(getBody());
		}
		else
		{
			writer(";");
			writer.nl;
		}
	}
	}
}

//Destructor:
//    [FunctionBody]
class Destructor : Node
{
	mixin ForwardCtor!();

	FunctionBody getBody() { return getMember!FunctionBody(0); }
	
	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("~this()");
		if(writer.writeImplementations)
		{
			writer.nl;
			writer(getBody());
		}
		else
		{
			writer(";");
			writer.nl;
		}
	}
	}
}

//Invariant:
//    [BlockStatement]
class Invariant : Node
{
	mixin ForwardCtor!();

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("invariant()");
		if(writer.writeImplementations)
		{
			writer.nl;
			writer(getMember(0));
		}
		else
		{
			writer(";");
			writer.nl;
		}
	}
	}
}

//ClassAllocator:
//    [Parameters FunctionBody]
class ClassAllocator : Node
{
	mixin ForwardCtor!();

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("new", getMember(0));
		writer.nl;
		writer(getMember(1));
	}
	}
}

//ClassDeallocator:
//    [Parameters FunctionBody]
class ClassDeallocator : Node
{
	mixin ForwardCtor!();

	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("delete", getMember(0));
		writer.nl;
		writer(getMember(1));
	}
	}
}


//AliasThis:
class AliasThis : Node
{
	string ident;
	
	mixin ForwardCtor!();

	this() {} // default constructor needed for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	
	public /* clone and compare */ { 
	override AliasThis clone()
	{
		AliasThis n = static_cast!AliasThis(super.clone());
		n.ident = ident;
		return n;
	}

	override bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	}
	public /* writer */ {
	override void toD(CodeWriter writer)
	{
		writer("alias ");
		writer.writeIdentifier(ident);
		writer(" this;");
		writer.nl;
	}
	}
}
