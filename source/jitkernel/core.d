module jitkernel.core;

import jitkernel.opengl;
import jitkernel.texture;
import jitkernel.vector;
import bindbc.opengl;

import std.conv : to;

private string ext (T) (ulong S = 1) {
	static if (is(T == bool)) return "bool";
	else static if (is(T == int)) return "int";
	else static if (is(T == Radian)) return "float";
	else static if (is(T == Degree)) return "float";
	else static if (is(T == Vector2)) return "vec2";
	else static if (is(T == Vector3)) return "vec3";
	else static if (is(T == Vector4)) return "vec4";
	else static if (is(T == Texture)) return "sampler2D";
	else static if (is(T == bool[])) return "bool["~to!string(S)~"]";
	else static if (is(T == int[])) return "int["~to!string(S)~"]";
	else static if (is(T == Radian[])) return "float["~to!string(S)~"]";
	else static if (is(T == Degree[])) return "float["~to!string(S)~"]";
	else static if (is(T == Vector2[])) return "vec2["~to!string(S)~"]";
	else static if (is(T == Vector3[])) return "vec3["~to!string(S)~"]";
	else static if (is(T == Vector4[])) return "vec4["~to!string(S)~"]";
	else static if (is(T == Texture[])) return "sampler2D["~to!string(S)~"]";
	else static assert(false);
}

public class KernelStored (T) {
	alias ElementType = T;
	IKernel kernel;
	string name;
	ulong arrayLength = 1;

	mixin KernelExpressions;

	this (IKernel _kernel = null, string _name = "", ulong _arrayLength = 1) {
		kernel = _kernel; name = _name; arrayLength = _arrayLength;
		name = (_name == "") ? kernel.genName() : _name;
	}
}

private template PromoteTypes(A, B) {
	static if (is(A == B))
		alias PromoteTypes = A;
	else static if (is(A == Radian) && (is(B == Vector2) || is(B == Vector3) || is(B == Vector4)))
		alias PromoteTypes = B;
	else static if ((is(A == Vector2) || is(A == Vector3) || is(A == Vector4)) && is(B == Radian))
		alias PromoteTypes = A;
	else
		static assert(false, "Cannot promote " ~ A.stringof ~ " and " ~ B.stringof);
}

private mixin template KernelExpressions () {
	// Assumes the surrounding class has a template parameter T,
	// fields `kernel`, `name`, `arrayLength`

	public auto opBinary (string op, V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) {
		alias ResultType = PromoteTypes!(T, ElementTypeFromArg!V);
		auto _v = kernel.asKernelStored!(ElementTypeFromArg!V)(v);
		KernelStored!ResultType ks = new KernelStored!ResultType(kernel);
		kernel.attachToMain(ext!(ResultType)() ~ " " ~ ks.name ~ "=" ~ name ~ op ~ _v.name ~ ";");
		return ks;
	}

	public auto opBinaryRight (string op, V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) {
		alias ResultType = PromoteTypes!(ElementTypeFromArg!V, T);
		auto _v = kernel.asKernelStored!(ElementTypeFromArg!V)(v);
		KernelStored!ResultType ks = new KernelStored!ResultType(kernel);
		kernel.attachToMain(ext!(ResultType)() ~ " " ~ ks.name ~ "=" ~ _v.name ~ op ~ name ~ ";");
		return ks;
	}

	public KernelStored!Radian clamp (A, B) (A a, B b) if (is(T == Radian) && StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B)) {
		auto _a = kernel.asKernelStored!Radian(a);
		auto _b = kernel.asKernelStored!Radian(b);
		KernelStored!Radian ks = new KernelStored!Radian(kernel);
		kernel.attachToMain(ext!(Radian)()~" "~ks.name~"=clamp("~name~","~_a.name~","~_b.name~");");
		return ks;
	}

	public KernelStored!R component (string c, R = ComponentToType!c) () if (validComponent!T(c) && validComponentExtract!(T, R)) {
		KernelStored!R ks = new KernelStored!R(kernel);
		kernel.attachToMain(ext!(R)()~" "~ks.name~"="~name~"."~c~";");
		return ks;
	}

	public auto opIndex (A) (A index) if (StoredOrLiteral!(int, A) && isKernelArray!T) {
		alias U = ArrayElementType!T;
		auto _index = kernel.asKernelStored!(ElementTypeFromArg!A)(index);
		KernelStored!U ks = new KernelStored!U(kernel);
		kernel.attachToMain(ext!(U)()~" "~ks.name~"="~name~"["~_index.name~"];");
		return ks;
	}

	public auto opIndexAssign (A, B) (B data, A index) if (StoredOrLiteral!(int, A) && isKernelArray!T && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!B) == ArrayElementType!T) {
		auto _index = kernel.asKernelStored!(ElementTypeFromArg!A)(index);
		auto _v = kernel.asKernelStored!(ElementTypeFromArg!B)(data);
		kernel.attachToMain(name~"["~_index.name~"]="~_v.name~";");
		return _v;
	}

	public auto opOpAssign(string op, V)(V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) {
		auto _v = kernel.asKernelStored!(ElementTypeFromArg!V)(v);
		kernel.attachToMain(name ~ op ~ "=" ~ _v.name ~ ";");
		return this;
	}

	public auto opCast(T) () {
		KernelStored!T ks = new KernelStored!T(kernel);
		kernel.attachToMain(ext!(T)()~" "~ks.name~"="~ext!(T)()~"("~name~");");
		return ks;
	}
}

public class KernelParameter (K) : KernelStored!K {
	public Uniform!K uniform;

	this (IKernel _kernel = null, string _name = "", ulong _arrayLength = 1) {
		super(_kernel, _name, _arrayLength);
	}

	this (IKernel _kernel = null, ulong _arrayLength = 1, string _name = "") {
		super(_kernel, _name, _arrayLength);
	}

	void set (K t) { uniform.set(t); }
}

private enum isKernelExpression(E) = is(typeof(E) : KernelStored!(E.ElementType));

private template ComponentToType (string c) {
	static if (c.length == 1) alias ComponentToType = Radian;
	else static if (c.length == 2) alias ComponentToType = Vector2;
	else static if (c.length == 3) alias ComponentToType = Vector3;
	else static if (c.length == 4) alias ComponentToType = Vector4;
	else static assert(false);
}

private template validComponentExtract (S, R) {
	enum validComponentExtract = false
	|| (is(S == Vector4) && (is(R == Vector4) || is(R == Vector3) || is(R == Vector2) || is(R == Radian)))
	|| (is(S == Vector3) && (is(R == Vector3) || is(R == Vector2) || is(R == Radian)))
	|| (is(S == Vector2) && (is(R == Vector2) || is(R == Radian)))
	;
}

private string[] validComponents(T)() if (KernelComponentBased!T) {
	import std.algorithm : canFind;
	static if (is(T == Vector2)) return ["xy","x","y","rg","r","g"];
	else static if (is(T == Vector3)) return ["xyz","xy","yz","x","y","z","rgb","rg","gb","r","g","b"];
	else static if (is(T == Vector4)) return [
		"xyzw","xyz","yzw","xy","yz","zw","x","y","z","w",
		"rgba","rgb","gba","rg","gb","ba","r","g","b","a",
	];
	else static assert(false);
}

private bool validComponent(T)(string component) if (KernelComponentBased!T) {
	import std.algorithm : canFind;
	return canFind(validComponents!T, component);
}

public enum StoredOrLiteral(T, V) = is(V : KernelStored!T) || (KernelLiteral!T && is(V : T));

private template ElementTypeFromArg(V) {
	static if (is(V : KernelStored!U, U)) alias ElementTypeFromArg = U;
	else static if (KernelLiteral!V) alias ElementTypeFromArg = V;
	else static assert(0, "Unsupported type: " ~ V.stringof);
}

private template ArrayElementType(T) {
	static if (is(T == bool[])) alias ArrayElementType = bool;
	else static if (is(T == int[])) alias ArrayElementType = int;
	else static if (is(T == Radian[])) alias ArrayElementType = Radian;
	else static if (is(T == Degree[])) alias ArrayElementType = Degree;
	else static if (is(T == Vector2[])) alias ArrayElementType = Vector2;
	else static if (is(T == Vector3[])) alias ArrayElementType = Vector3;
	else static if (is(T == Vector4[])) alias ArrayElementType = Vector4;
	else static if (is(T == Texture[])) alias ArrayElementType = Texture;
	else static assert(false, "Unsupported array type: " ~ T.stringof);
}

private enum isKernelArray(T) = is(T == bool[]) || is(T == int[]) || is(T == Radian[]) || is(T == Degree[]) || is(T == Vector2[]) || is(T == Vector3[]) || is(T == Vector4[]) || is(T == Texture[]);

public interface IKernel {
	public void attachToSetup (string data);
	public void attachToMain (string data);
	public string genName ();
	public KernelStored!Vector2 compose (A, B) (A a, B b) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B));
	public KernelStored!Vector3 compose (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B) && StoredOrLiteral!(Radian, C));
	public KernelStored!Vector4 compose (A, B, C, D) (A a, B b, C c, D d) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B) && StoredOrLiteral!(Radian, C) && StoredOrLiteral!(Radian, D));
	public KernelStored!Radian clamp (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B) && StoredOrLiteral!(Radian, C));
	public KernelStored!(ElementTypeFromArg!A) mix (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && StoredOrLiteral!(ElementTypeFromArg!C, C) && is(ElementTypeFromArg!A == ElementTypeFromArg!B) && (is(ElementTypeFromArg!C == ElementTypeFromArg!A) || is(ElementTypeFromArg!C == Radian)));
	public KernelStored!(ElementTypeFromArg!A) pow (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B) || is(ElementTypeFromArg!B == Radian)));
	public KernelStored!(ElementTypeFromArg!A) min (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B));
	public KernelStored!(ElementTypeFromArg!A) max (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B));
	public KernelStored!(ElementTypeFromArg!A) dot (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B));
	public KernelStored!(ElementTypeFromArg!V) sin (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!V) cos (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!V) tan (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!V) abs (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!V) atan (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!V) atan2 (V) (V y, V x) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!V) normalize (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V));
	public KernelStored!(ElementTypeFromArg!T) op (T, A, B) (A a, string op, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B));
	public KernelStored!Vector4 sample (A) (KernelStored!Texture tex, A a) if (StoredOrLiteral!(Vector2, A));
	public void output (A) (A a) if (StoredOrLiteral!(Vector4, A));
	public void earlyOutput (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!bool, A) && StoredOrLiteral!(ElementTypeFromArg!Vector4, B));
	public void branch (A) (A a, void delegate (Kernel) positive, void delegate (Kernel) negative) if (StoredOrLiteral!(ElementTypeFromArg!bool, A));
	public void loop (A, B) (A begin, string checkOp = "<", B until, string updateOp = "++", void delegate (Kernel, KernelStored!(ElementTypeFromArg!A)) eval) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B));
	public KernelStored!(ElementTypeFromArg!B) step (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B));
	public KernelStored!(ElementTypeFromArg!C) smoothstep (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && StoredOrLiteral!(ElementTypeFromArg!C, C) && is(ElementTypeFromArg!A == ElementTypeFromArg!B) && (is(ElementTypeFromArg!C == ElementTypeFromArg!A) || is(ElementTypeFromArg!C == Radian)));
	public KernelStored!Vector3 cross (A, B) (A a, B b) if (StoredOrLiteral!(Vector3, A) && StoredOrLiteral!(Vector3, B));
	public KernelStored!(ElementTypeFromArg!A) reflect (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B)));
	public KernelStored!(ElementTypeFromArg!A) refract (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B)) && StoredOrLiteral!(Radian, C));
	public KernelStored!(ElementTypeFromArg!A) distance (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B)));
	public KernelStorattachToSetuped!(ElementTypeFromArg!A) faceforward (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && StoredOrLiteral!(ElementTypeFromArg!C, C) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B)) && (is(ElementTypeFromArg!A == ElementTypeFromArg!C)));
	public KernelStored!Radian length (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V) && KernelComponentBased!(ElementTypeFromArg!V));
	public void break_ ();
	public void discard ();
	public void exit ();

	public KernelStored!T asKernelStored(T, A)(A a)
        if (is(A : KernelStored!T) || (KernelLiteral!T && is(A : T)))
    {
        static if (is(A : KernelStored!T)) {
            return a;
        } else {
            KernelStored!T ks = new KernelStored!T(this, genName());
            attachToSetup("const " ~ ext!T() ~ " " ~ ks.name ~ "=" ~ serialize!T(a) ~ ";");
            return ks;
        }
    }
}

public class Kernel (KernelData) : IKernel {
	private int nameCount = 0;
	public string genName () {
		return "_jitkernel"~to!string(nameCount++);
	}

	import core.sync.mutex;
	private Mutex mtx;
	public KernelData data;
	private string setupCompose = "";
	public void attachToSetup (string data) { setupCompose ~= data; }
	private string main = "";
	public void attachToMain (string data) { main ~= data; }
	private void delegate(GLint)[string] lateUniformUpdate;
	private void delegate(int*)[string] upload;
	public void delegate(Kernel, Vector4, ref KernelData)[] prehooks;
	public void delegate(Kernel, Vector4, ref KernelData)[] posthooks;
	private Shader shader;
	
	public KernelStored!Vector4 coord;
	public KernelStored!Vector2 uv;
	
	public KernelStored!Radian e;
	public KernelStored!Radian pi;
	public KernelStored!Radian epsilon;
	public KernelStored!Radian zero;
	public KernelStored!Radian one;
	public KernelStored!Radian two;
	
	public this () {
		mtx = new Mutex();
		coord = new KernelStored!Vector4(this, "gl_FragCoord");
		uv = new KernelStored!Vector2(this, "uv");
		import std.math;
		pi = literal(Radian(std.math.PI));
		epsilon = literal(Radian.zero.epsilon);
		e = literal(Radian(std.math.E));
		zero = literal(Radian.zero);
		one = literal(Radian.one);
		two = literal(Radian.two);
	}
	public static Kernel create () { return new Kernel(); }
	public this (void delegate (Kernel, ref KernelData) setup) { this(); setup(this, data); }
	public static Kernel create (void delegate (Kernel, ref KernelData) setup) { return new Kernel(setup); }
	public void compute (void delegate (Kernel, ref KernelData) setup) { setup(this, data); }

	public void draw (Texture target, Vector4 area, KernelData input) {
		synchronized (mtx) {
			data = input;
			if (shader is null) build();
			foreach (void delegate(Kernel, Vector4, ref KernelData) hook; prehooks) hook(this, area, data);
			shader.draw(target, area);
			foreach (void delegate(Kernel, Vector4, ref KernelData) hook; posthooks) hook(this, area, data);
		}
	}

	public KernelParameter!T uniform (T) (ulong arrayLength = 1) {
		KernelParameter!T ku = new KernelParameter!T(this, arrayLength);
		ku.uniform = new Uniform!T(ku.name, 0, T.init);
		setupCompose ~= "uniform "~ext!T(arrayLength)~" "~ku.uniform.name~";";
		lateUniformUpdate[ku.uniform.name] = (GLint i) { ku.uniform.location = i; };
		upload[ku.uniform.name] = (int* i) => ku.uniform.upload(i);
		return ku;
	}

	public KernelStored!T link (T) (ref T data, ulong arrayLength = 1) {
		KernelParameter!T u = uniform!T(arrayLength);
		prehook((Kernel!KernelData k, Vector4 area, ref KernelData _) { u.set(data); });
		return u;
	}

	public KernelStored!int define (int value) {
		KernelStored!int ks = new KernelStored!int(this);
		setupCompose ~= "\n#define "~ks.name~" "~to!string(value)~"\n";
		return ks;
	}

	public KernelStored!T literal (T) (T literal) if (KernelLiteral!T) {
		KernelStored!T ks = new KernelStored!T(this, genName());
		setupCompose ~= "const "~ext!(T)()~" "~ks.name~"="~serialize!T(literal)~";";
		return ks;
	}

	public KernelStored!T array (T) (ulong arraySize) if (KernelLiteral!T) {
		KernelStored!T ks = new KernelStored!T(this, genName(), arraySize);
		main ~= ext!(T)(arraySize)~" "~ks.name~";";
		return ks;
	}

	public KernelStored!Vector2 compose (A, B) (A a, B b) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B)) { alias T = Vector2; auto _a = asKernelStored!Radian(a); auto _b = asKernelStored!Radian(b); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=vec2("~_a.name~","~_b.name~");"; return ks; }
	public KernelStored!Vector3 compose (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B) && StoredOrLiteral!(Radian, C)) { alias T = Vector3; auto _a = asKernelStored!Radian(a); auto _b = asKernelStored!Radian(b); auto _c = asKernelStored!Radian(c); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=vec3("~_a.name~","~_b.name~","~_c.name~");"; return ks; }
	public KernelStored!Vector4 compose (A, B, C, D) (A a, B b, C c, D d) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B) && StoredOrLiteral!(Radian, C) && StoredOrLiteral!(Radian, D)) { alias T = Vector4; auto _a = asKernelStored!Radian(a); auto _b = asKernelStored!Radian(b); auto _c = asKernelStored!Radian(c); auto _d = asKernelStored!Radian(d); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=vec4("~_a.name~","~_b.name~","~_c.name~","~_d.name~");"; return ks; }
	public KernelStored!Radian clamp (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(Radian, A) && StoredOrLiteral!(Radian, B) && StoredOrLiteral!(Radian, C)) { alias T = Radian; auto _a = asKernelStored!Radian(a); auto _b = asKernelStored!Radian(b); auto _c = asKernelStored!Radian(c); KernelStored!Radian ks = new KernelStored!Radian(this); main ~= ext!Radian()~" "~ks.name~"=clamp("~_a.name~","~_b.name~","~_c.name~");"; return ks; }
	public auto mix (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && StoredOrLiteral!(ElementTypeFromArg!C, C) && is(ElementTypeFromArg!A == ElementTypeFromArg!B) && (is(ElementTypeFromArg!C == ElementTypeFromArg!A) || is(ElementTypeFromArg!C == Radian))) { alias T = ElementTypeFromArg!A; auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); auto _c = asKernelStored!(ElementTypeFromArg!C)(c); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=mix("~_a.name~","~_b.name~","~_c.name~");"; return ks; }
	public auto pow (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B) || is(ElementTypeFromArg!B == Radian))) { alias T = ElementTypeFromArg!A; auto _a = asKernelStored!T(a); auto _b = asKernelStored!T(b); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=pow("~_a.name~","~_b.name~");"; return ks; }
	public auto min (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B)) { alias T = ElementTypeFromArg!A; auto _a = asKernelStored!T(a); auto _b = asKernelStored!T(b); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=min("~_a.name~","~_b.name~");"; return ks; }
	public auto max (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B)) { alias T = ElementTypeFromArg!A; auto _a = asKernelStored!T(a); auto _b = asKernelStored!T(b); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=max("~_a.name~","~_b.name~");"; return ks; }
	public auto dot (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); KernelStored!Radian ks = new KernelStored!Radian(this); main ~= ext!Radian()~" "~ks.name~"=dot("~_a.name~","~_b.name~");"; return ks; }
	public auto sin (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _v = asKernelStored!T(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=sin(" ~ _v.name ~ ");"; return ks; }
	public auto cos (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _v = asKernelStored!T(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=cos(" ~ _v.name ~ ");"; return ks; }
	public auto tan (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _v = asKernelStored!T(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=tan(" ~ _v.name ~ ");"; return ks; }
	public auto abs (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _v = asKernelStored!T(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=abs(" ~ _v.name ~ ");"; return ks; }
	public auto atan (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _v = asKernelStored!T(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=atan(" ~ _v.name ~ ");"; return ks; }
	public auto atan2 (V) (V y, V x) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _y = asKernelStored!T(y); auto _x = asKernelStored!T(x); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=atan(" ~ _y.name ~ "," ~ _x.name ~ ");"; return ks; }
	public auto normalize (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V)) { alias T = ElementTypeFromArg!V; auto _v = asKernelStored!T(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=normalize(" ~ _v.name ~ ");"; return ks; }
	public KernelStored!T op (T, A, B) (A a, string op, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"="~_a.name~op~_b.name~";"; return ks; }
	public KernelStored!Vector4 sample (A) (KernelStored!Texture tex, A a) if (StoredOrLiteral!(Vector2, A)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); KernelStored!Vector4 ks = new KernelStored!Vector4(this); main ~= ext!Vector4()~" "~ks.name~"=texture("~tex.name~","~_a.name~");"; return ks; }
	public void output (A) (A a) if (StoredOrLiteral!(Vector4, A)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); main ~= "finalColor="~_a.name~";"; }
	public void earlyOutput (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!bool, A) && StoredOrLiteral!(ElementTypeFromArg!Vector4, B)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); main ~= "if("~_a.name~"){finalColor="~_b.name~";return;}"; }
	public void branch (A) (A a, void delegate (Kernel) positive, void delegate (Kernel) negative) if (StoredOrLiteral!(ElementTypeFromArg!bool, A)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); main~="if("~_a.name~"){";positive(this);main~="}else{";negative(this);main~="}";}
	public void loop (A, B) (A begin, string checkOp = "<", B until, string updateOp = "++", void delegate (Kernel, KernelStored!(ElementTypeFromArg!A)) eval) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && is(ElementTypeFromArg!A == ElementTypeFromArg!B)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(begin); auto _b = asKernelStored!(ElementTypeFromArg!A)(until); auto i = new KernelStored!(ElementTypeFromArg!A)(this, genName()); main~="for("~ext!(ElementTypeFromArg!A)()~" "~i.name~"="~_a.name~";"~i.name~checkOp~_b.name~";"~i.name~updateOp~"){"; eval(this, i); main~="}"; }

	public KernelStored!(ElementTypeFromArg!B) step (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); alias T = ElementTypeFromArg!B; KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=step("~_a.name~","~_b.name~");"; return ks; }
	public KernelStored!(ElementTypeFromArg!C) smoothstep (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && StoredOrLiteral!(ElementTypeFromArg!C, C) && is(ElementTypeFromArg!A == ElementTypeFromArg!B) && (is(ElementTypeFromArg!C == ElementTypeFromArg!A) || is(ElementTypeFromArg!C == Radian))) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); auto _c = asKernelStored!(ElementTypeFromArg!C)(c); alias T = ElementTypeFromArg!C; KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=smoothstep("~_a.name~","~_b.name~","~_c.name~");"; return ks; }
	public KernelStored!Vector3 cross (A, B) (A a, B b) if (StoredOrLiteral!(Vector3, A) && StoredOrLiteral!(Vector3, B)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); alias T = Vector3; KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=cross("~_a.name~","~_b.name~");"; return ks; }
	public auto reflect (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B))) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); alias T = ElementTypeFromArg!A; KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=reflect("~_a.name~","~_b.name~");"; return ks; }
	public auto refract (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B)) && StoredOrLiteral!(Radian, C)) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); auto _c = asKernelStored!(ElementTypeFromArg!C)(c); alias T = ElementTypeFromArg!A; KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=refract("~_a.name~","~_b.name~","~_c.name~");"; return ks; }
	public KernelStored!Radian length (V) (V v) if (StoredOrLiteral!(ElementTypeFromArg!V, V) && KernelComponentBased!(ElementTypeFromArg!V)) { alias T = Radian; auto _v = asKernelStored!(ElementTypeFromArg!V)(v); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T() ~ " " ~ ks.name ~ "=length(" ~ _v.name ~ ");"; return ks; }
	public auto distance (A, B) (A a, B b) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B))) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); alias T = KernelStoredLength!(ElementTypeFromArg!A); KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=distance("~_a.name~","~_b.name~");"; return ks; }
	public auto faceforward (A, B, C) (A a, B b, C c) if (StoredOrLiteral!(ElementTypeFromArg!A, A) && StoredOrLiteral!(ElementTypeFromArg!B, B) && StoredOrLiteral!(ElementTypeFromArg!C, C) && (is(ElementTypeFromArg!A == ElementTypeFromArg!B)) && (is(ElementTypeFromArg!A == ElementTypeFromArg!C))) { auto _a = asKernelStored!(ElementTypeFromArg!A)(a); auto _b = asKernelStored!(ElementTypeFromArg!B)(b); auto _c = asKernelStored!(ElementTypeFromArg!C)(c); alias T = ElementTypeFromArg!A; KernelStored!T ks = new KernelStored!T(this); main ~= ext!T()~" "~ks.name~"=faceforward("~_a.name~","~_b.name~","~_c.name~");"; return ks; }
	public void break_ () { main ~= "break;"; }
	public void discard () { main ~= "discard;"; }
	public void exit () { main ~= "return;"; }
	
	public string exportCode () {
		return "#version 330 core\nin vec2 uv;out vec4 finalColor;"
		~ setupCompose
		~ "void main () {"
		~ main
		~ "}";
	}

	public Shader build () {
		try {
			debug { import std.stdio : writeln; try { writeln("rebuilt shader", &(this.shader)); } catch (Exception) {} }
			shader = new Shader(exportCode());
			foreach (string name, void delegate(GLint) hook; lateUniformUpdate) {
				import std.string;
				GLint location = shader.address(name);
				lateUniformUpdate[name](location);
				shader.hook(upload[name]);
			}
			return shader;
		} catch (Exception err) {
			debug { import std.stdio : writeln; try { writeln(exportCode()); } catch (Exception) {} }
			throw err;
		}
	}

	public void prehook (void delegate (Kernel, Vector4, ref KernelData) hook) {
		prehooks ~= hook;
	}

	public void posthook (void delegate (Kernel, Vector4, ref KernelData) hook) {
		posthooks ~= hook;
	}
}

private template StoredOrLiteral (A) {
	enum StoredOrLiteral = (is(A : KernelStored!T) || (KernelLiteral!T && is(A : T)));
}

private template KernelLiteral (T) {
	enum KernelLiteral = is(T == bool) ||is(T == int) || is(T == Radian) || is(T == Vector2) || is(T == Vector3) || is(T == Vector4);
}

private template KernelStoredLength (T) {
	static if (is(T == int)) alias KernelStoredLength = int;
	static if (is(T == Radian) || KernelComponentBased!T) alias KernelStoredLength = Radian;
}

private template KernelComponentBased (T) {
	enum KernelComponentBased = is(T == Vector2) || is(T == Vector3) || is(T == Vector4);
}

private string serialize (T) (T literal) {
	static if (is(T == bool)) return to!string(literal);
	static if (is(T == int)) return to!string(literal);
	else static if (is(T == Radian)) return to!string(literal.raw);
	else static if (is(T == Degree)) return to!string(literal.rad.raw);
	else static if (is(T == Vector2)) return "vec2("~to!string(literal.x.raw)~","~to!string(literal.y.raw)~")";
	else static if (is(T == Vector3)) return "vec3("~to!string(literal.x.raw)~","~to!string(literal.y.raw)~","~to!string(literal.z.raw)~")";
	else static if (is(T == Vector4)) return "vec4("~to!string(literal.x.raw)~","~to!string(literal.y.raw)~","~to!string(literal.z.raw)~","~to!string(literal.w.raw)~")";
	else static assert (false);
}

public KernelStored translateUV (K) (K k, KernelStored!Vector4 source, KernelStored!Vector4 target) {
	return k.mix(
		source.component!"xy",
		source.component!"zw",
		(k.coord.component!"xy" - target.component!"xy")
		/ target.component!"zw"
	);
}

/*
public template Effect (T, void delegate (Kernel, KernelParameter!T) handler) {
	public class Effect {
		import core.sync.mutex;
		public __gshared Mutex mut = new Mutex();
		public __gshared KernelParameter!T payload;
		public __gshared kernel = new Kernel((Kernel k) {handler(k, payload);});
		public static void draw (Texture target, Vector4 rect, T data) {
			synchronized (mut) {
				payload.set(data);
				kernel.draw(target, rect);
			}
		}
	}
}

alias UV = Effect!(Radian, (Kernel k, KernelParameter!Radian p) {});

*/
