=====================================
HLSL to SPIR-V Feature Mapping Manual
=====================================

.. contents::
   :local:
   :depth: 3

Introduction
============

This document describes the mappings from HLSL features to SPIR-V for Vulkan
adopted by the SPIR-V codegen. For how to build, use, or contribute to the
SPIR-V codegen and its internals, please see the
`wiki <https://github.com/Microsoft/DirectXShaderCompiler/wiki/SPIR%E2%80%90V-CodeGen>`_
page.

`SPIR-V <https://www.khronos.org/registry/spir-v/>`_ is a binary intermediate
language for representing graphical-shader stages and compute kernels for
multiple Khronos APIs, such as Vulkan, OpenGL, and OpenCL. At the moment we
only intend to support the Vulkan flavor of SPIR-V.

DirectXShaderCompiler is the reference compiler for HLSL. Adding SPIR-V codegen
in DirectXShaderCompiler will enable the usage of HLSL as a frontend language
for Vulkan shader programming. Sharing the same code base also means we can
track the evolution of HLSL more closely and always deliver the best of HLSL to
developers. Moreover, developers will also have a unified compiler toolchain for
targeting both DirectX and Vulkan. We believe this effort will benefit the
general graphics ecosystem.

Note that this document is expected to be an ongoing effort and grow as we
implement more and more HLSL features.

Vulkan Semantics
================

Note that the term "semantic" is overloaded. In HLSL, it can mean the string
attached to shader input or output. For such cases, we refer it as "HLSL
semantic" or "semantic string". For other cases, we just use the normal
"semantic" term.

Due to the differences of semantics between DirectX and Vulkan, certain HLSL
features do not have corresponding mappings in Vulkan, and certain Vulkan
specific information does not have native ways to express in HLSL source code.

To provide additional information required by Vulkan in HLSL, we need to extend
the syntax of HLSL.
`C++ attribute specifier sequence <http://en.cppreference.com/w/cpp/language/attributes>`_
is a non-intrusive way of achieving such purpose.

For example, to specify the layout of resource variables and the location of
interface variables:

.. code:: hlsl

  struct S { ... };

  [[vk::binding(X, Y)]]
  StructuredBuffer<S> mySBuffer;

  [[vk::location(M)]] float4
  main([[vk::location(N)]] float4 input: A) : B
  { ... }

The namespace ``vk`` will be used for all Vulkan attributes:

- ``location(X)``: For specifying the location (``X``) numbers for stage
  input/output variables. Allowed on function parameters, function returns,
  and struct fields.
- ``binding(X[, Y])``: For specifying the descriptor set (``Y``) and binding
  (``X``) numbers for resource variables. The descriptor set (``Y``) is
  optional; if missing, it will be set to 0. Allowed on global variables.

Only ``vk::`` attributes in the above list are supported. Other attributes will
result in warnings and be ignored by the compiler. All C++11 attributes will
only trigger warnings and be ignored if not compiling towards SPIR-V.

HLSL Types
==========

This section lists how various HLSL types are mapped.

Normal scalar types
-------------------

`Normal scalar types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509646(v=vs.85).aspx>`_
in HLSL are relatively easy to handle and can be mapped directly to SPIR-V
type instructions:

================== ================== =========== ====================
      HLSL               SPIR-V       Capability       Decoration
================== ================== =========== ====================
``bool``           ``OpTypeBool``
``int``            ``OpTypeInt 32 1``
``uint``/``dword`` ``OpTypeInt 32 0``
``half``           ``OpTypeFloat 32``             ``RelexedPrecision``
``float``          ``OpTypeFloat 32``
``double``         ``OpTypeFloat 64`` ``Float64``
================== ================== =========== ====================

Please note that ``half`` is translated into 32-bit floating point numbers
right now because MSDN says that "this data type is provided only for language
compatibility. Direct3D 10 shader targets map all ``half`` data types to
``float`` data types." This may change in the future to map to 16-bit floating
point numbers (possibly via a command-line option).

Note: ``float`` and ``double`` not implemented yet

Minimal precision scalar types
------------------------------

HLSL also supports various
`minimal precision scalar types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509646(v=vs.85).aspx>`_,
which graphics drivers can implement by using any precision greater than or
equal to their specified bit precision.
There are no direct mappings in SPIR-V for these types. We translate them into
the corresponding 32-bit scalar types with the ``RelexedPrecision`` decoration:

============== ================== ====================
    HLSL            SPIR-V            Decoration
============== ================== ====================
``min16float`` ``OpTypeFloat 32`` ``RelexedPrecision``
``min10float`` ``OpTypeFloat 32`` ``RelexedPrecision``
``min16int``   ``OpTypeInt 32 1`` ``RelexedPrecision``
``min12int``   ``OpTypeInt 32 1`` ``RelexedPrecision``
``min16uint``  ``OpTypeInt 32 0`` ``RelexedPrecision``
============== ================== ====================

Note: not implemented yet

Vectors and matrices
--------------------

`Vectors <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509707(v=vs.85).aspx>`_
and `matrices <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509623(v=vs.85).aspx>`_
are translated into:

==================================== ====================================================
              HLSL                                         SPIR-V
==================================== ====================================================
``|type|N`` (``N`` > 1)              ``OpTypeVector |type| N``
``|type|1``                          The scalar type for ``|type|``
``|type|MxN`` (``M`` > 1, ``N`` > 1) ``%v = OpTypeVector |type| N`` ``OpTypeMatrix %v M``
``|type|Mx1`` (``M`` > 1)            ``OpTypeVector |type| M``
``|type|1xN`` (``N`` > 1)            ``OpTypeVector |type| N``
``|type|1x1``                        The scalar type for ``|type|``
==================================== ====================================================

A MxN HLSL matrix is translated into a SPIR-V matrix with M vectors, each with
N elements. Conceptually HLSL matrices are row-major while SPIR-V matrices are
column-major, thus all HLSL matrices are represented by their transposes.
Doing so may require special handling of certain matrix operations:

- **Indexing**: no special handling required. ``matrix[m][n]`` will still access
  the correct element since ``m``/``n`` means the ``m``-th/``n``-th row/column
  in HLSL but ``m``-th/``n``-th vector/element in SPIR-V.
- **Per-element operation**: no special handling required.
- **Matrix multiplication**: need to swap the operands. ``mat1 x mat2`` should
  be translated as ``transpose(mat2) x transpose(mat1)``. Then the result is
  ``transpose(mat1 x mat2)``.
- **Storage layout**: ``row_major``/``column_major`` will be translated into
  SPIR-V ``ColMajor``/``RowMajor`` decoration. This is because HLSL matrix
  row/column becomes SPIR-V matrix column/row. If elements in a row/column are
  packed together, they should be loaded into a column/row correspondingly.

Structs
-------

`Structs <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509668(v=vs.85).aspx>`_
in HLSL are defined in the a format similar to C structs. They are translated
into SPIR-V ``OpTypeStruct``. Depending on the storage classes of the instances,
a single struct definition may generate multiple ``OpTypeStruct`` instructions
in SPIR-V. For example, for the following HLSL source code:

.. code:: hlsl

  struct S { ... }

  ConstantBuffer<S>   myCBuffer;
  StructuredBuffer<S> mySBuffer;

  float4 main() : A {
    S myLocalVar;
    ...
  }

There will be there different ``OpTypeStruct`` generated, one for each variable
defined in the above source code. This is because the ``OpTypeStruct`` for
both ``myCBuffer`` and ``mySBuffer`` will have layout decorations (``Offset``,
``MatrixStride``, ``ArrayStride``, ``RowMajor``, ``ColMajor``). However, their
layout rules are different (by default); ``myCBuffer`` will use GLSL ``std140``
while ``mySBuffer`` will use GLSL ``std430``. ``myLocalVar`` will have its
``OpTypeStruct`` without layout decorations. Read more about storage classes
in the `Buffers`_ section.

Structs used as stage inputs/outputs will have semantics attached to their
members. These semantics are handled in the `entry function wrapper`_.

Structs used as pixel shader inputs can have optional interpolation modifiers
for their members, which will be translated according to the following table:

=========================== ================= =====================
HLSL Interpolation Modifier SPIR-V Decoration   SPIR-V Capability
=========================== ================= =====================
``linear``                  <none>
``centroid``                ``Centroid``
``nointerpolation``         ``Flat``
``noperspective``           ``NoPerspective``
``sample``                  ``Sample``        ``SampleRateShading``
=========================== ================= =====================

User-defined types
------------------

`User-defined types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509702(v=vs.85).aspx>`_
are type aliases introduced by typedef. No new types are introduced and we can
rely on Clang to resolve to the original types.

Samplers
--------

All `sampler types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509644(v=vs.85).aspx>`_
will be translated into SPIR-V ``OpTypeSampler``.

SPIR-V ``OpTypeSampler`` is an opaque type that cannot be parameterized;
therefore state assignments on sampler types is not supported (yet).

Textures
--------

`Texture types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509700(v=vs.85).aspx>`_
are translated into SPIR-V ``OpTypeImage``, with parameters:

======================= ========== ===== ======= == ======= ================ =================
HLSL Texture Type           Dim    Depth Arrayed MS Sampled  Image Format       Capability
======================= ========== ===== ======= == ======= ================ =================
``Texture1D``           ``1D``      0       0    0    1     ``Unknown``
``Texture2D``           ``2D``      0       0    0    1     ``Unknown``
``Texture3D``           ``3D``      0       0    0    1     ``Unknown``
``TextureCube``         ``Cube``    0       0    0    1     ``Unknown``
``Texture1DArray``      ``1D``      0       1    0    1     ``Unknown``
``Texture2DArray``      ``2D``      0       1    0    1     ``Unknown``
``Texture2DMS``         ``2D``      0       0    1    1     ``Unknown``
``Texture2DMSArray``    ``2D``      0       1    1    1     ``Unknown``      ``ImageMSArray``
``TextureCubeArray``    ``3D``      0       1    0    1     ``Unknown``
``Buffer<T>``           ``Buffer``  0       0    0    1     Depends on ``T`` ``SampledBuffer``
``RWBuffer<T>``         ``Buffer``  0       0    0    2     Depends on ``T`` ``SampledBuffer``
``RWTexture1D<T>``      ``1D``      0       0    0    2     Depends on ``T``
``RWTexture2D<T>``      ``2D``      0       0    0    2     Depends on ``T``
``RWTexture3D<T>``      ``3D``      0       0    0    2     Depends on ``T``
``RWTexture1DArray<T>`` ``1D``      0       1    0    2     Depends on ``T``
``RWTexture2DArray<T>`` ``2D``      0       1    0    2     Depends on ``T``
======================= ========== ===== ======= == ======= ================ =================

The meanings of the headers in the above table is explained in ``OpTypeImage``
of the SPIR-V spec.

Buffers
-------

There are serveral buffer types in HLSL:

- ``cbuffer`` and ``ConstantBuffer``
- ``tbuffer`` and ``TextureBuffer``
- ``StructuredBuffer`` and ``RWStructuredBuffer``
- ``AppendStructuredBuffer`` and ``ConsumeStructuredBuffer``

Please see the following sections for the details of each type. As a summary:

=========================== ================== ========================== ==================== =================
         HLSL Type          Vulkan Buffer Type Default Memory Layout Rule SPIR-V Storage Class SPIR-V Decoration
=========================== ================== ========================== ==================== =================
``cbuffer``                   Uniform Buffer      GLSL ``std140``            ``Uniform``        ``Block``
``ConstantBuffer``            Uniform Buffer      GLSL ``std140``            ``Uniform``        ``Block``
``StructuredBuffer``          Storage Buffer      GLSL ``std430``            ``Uniform``        ``BufferBlock``
``RWStructuredBuffer``        Storage Buffer      GLSL ``std430``            ``Uniform``        ``BufferBlock``
``AppendStructuredBuffer``    Storage Buffer      GLSL ``std430``            ``Uniform``        ``BufferBlock``
``ConsumeStructuredBuffer``   Storage Buffer      GLSL ``std430``            ``Uniform``        ``BufferBlock``
=========================== ================== ========================== ==================== =================

To know more about the Vulkan buffer types, please refer to the Vulkan spec
`13.1 Descriptor Types <https://www.khronos.org/registry/vulkan/specs/1.0-wsi_extensions/html/vkspec.html#descriptorsets-types>`_.

``cbuffer`` and ``ConstantBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

These two buffer types are treated as uniform buffers using Vulkan's
terminology. They are translated into an ``OpTypeStruct`` with the
necessary layout decorations (``Offset``, ``ArrayStride``, ``MatrixStride``,
``RowMajor``, ``ColMajor``) and the ``Block`` decoration. The layout rule
used is GLSL ``std140`` (by default). A variable declared as one of these
types will be placed in the ``Uniform`` storage class.

For example, for the following HLSL source code:

.. code:: hlsl

  struct T {
    float  a;
    float3 b;
  };

  ConstantBuffer<T> myCBuffer;

will be translated into

.. code:: spirv

  ; Layout decoration
  OpMemberDecorate %type_ConstantBuffer_T 0 Offset 0
  OpMemberDecorate %type_ConstantBuffer_T 0 Offset 16
  ; Block decoration
  OpDecorate %type_ConstantBuffer_T Block

  ; Types
  %type_ConstantBuffer_T = OpTypeStruct %float %v3float
  %_ptr_Uniform_type_ConstantBuffer_T = OpTypePointer Uniform %type_ConstantBuffer_T

  ; Variable
  %myCbuffer = OpVariable %_ptr_Uniform_type_ConstantBuffer_T Uniform

``StructuredBuffer`` and ``RWStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``StructuredBuffer<T>``/``RWStructuredBuffer<T>`` is treated as storage buffer
using Vulkan's terminology. It is translated into an ``OpTypeStruct`` containing
an ``OpTypeRuntimeArray`` of type ``T``, with necessary layout decorations
(``Offset``, ``ArrayStride``, ``MatrixStride``, ``RowMajor``, ``ColMajor``) and
the ``BufferBlock`` decoration.  The default layout rule used is GLSL
``std430``. A variable declared as one of these types will be placed in the
``Uniform`` storage class.

For example, for the following HLSL source code:

.. code:: hlsl

  struct T {
    float  a;
    float3 b;
  };

  StructuredBuffer<T> mySBuffer;

will be translated into

.. code:: spirv

  ; Layout decoration
  OpMemberDecorate %T 0 Offset 0
  OpMemberDecorate %T 1 Offset 16
  OpDecorate %_runtimearr_T ArrayStride 32
  OpMemberDecorate %type_StructuredBuffer_T 0 Offset 0
  OpMemberDecorate %type_StructuredBuffer_T 0 NoWritable
  ; BufferBlock decoration
  OpDecorate %type_StructuredBuffer_T BufferBlock

  ; Types
  %T = OpTypeStruct %float %v3float
  %_runtimearr_T = OpTypeRuntimeArray %T
  %type_StructuredBuffer_T = OpTypeStruct %_runtimearr_T
  %_ptr_Uniform_type_StructuredBuffer_T = OpTypePointer Uniform %type_StructuredBuffer_T

  ; Variable
  %myCbuffer = OpVariable %_ptr_Uniform_type_ConstantBuffer_T Uniform

``AppendStructuredBuffer`` and ``ConsumeStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``AppendStructuredBuffer<T>``/``ConsumeStructuredBuffer<T>`` is treated as
storage buffer using Vulkan's terminology. It is translated into an
``OpTypeStruct`` containing an ``OpTypeRuntimeArray`` of type ``T``, with
necessary layout decorations (``Offset``, ``ArrayStride``, ``MatrixStride``,
``RowMajor``, ``ColMajor``) and the ``BufferBlock`` decoration. The default
layout rule used is GLSL ``std430``.

A variable declared as one of these types will be placed in the ``Uniform``
storage class. Besides, each variable will have an associated counter variable
generated. The counter variable will be of ``OpTypeStruct`` type, which only
contains a 32-bit integer. The counter variable takes its own binding number.
``.Append()``/``.Consume()`` will use the counter variable as the index and
adjust it accordingly.

For example, for the following HLSL source code:

.. code:: hlsl

  struct T {
    float  a;
    float3 b;
  };

  AppendStructuredBuffer<T> mySBuffer;

will be translated into

.. code:: spirv

  ; Layout decorations
  OpMemberDecorate %T 0 Offset 0
  OpMemberDecorate %T 1 Offset 16
  OpDecorate %_runtimearr_T ArrayStride 32
  OpMemberDecorate %type_AppendStructuredBuffer_T 0 Offset 0
  OpDecorate %type_AppendStructuredBuffer_T BufferBlock
  OpMemberDecorate %type_ACSBuffer_counter 0 Offset 0
  OpDecorate %type_ACSBuffer_counter BufferBlock

  ; Binding numbers
  OpDecorate %myASbuffer DescriptorSet 0
  OpDecorate %myASbuffer Binding 0
  OpDecorate %counter_var_myASbuffer DescriptorSet 0
  OpDecorate %counter_var_myASbuffer Binding 1

  ; Types
  %T = OpTypeStruct %float %v3float
  %_runtimearr_T = OpTypeRuntimeArray %T
  %type_AppendStructuredBuffer_T = OpTypeStruct %_runtimearr_T
  %_ptr_Uniform_type_AppendStructuredBuffer_T = OpTypePointer Uniform %type_AppendStructuredBuffer_T
  %type_ACSBuffer_counter = OpTypeStruct %int
  %_ptr_Uniform_type_ACSBuffer_counter = OpTypePointer Uniform %type_ACSBuffer_counter

  ; Variables
  %myASbuffer = OpVariable %_ptr_Uniform_type_AppendStructuredBuffer_T Uniform
  %counter_var_myASbuffer = OpVariable %_ptr_Uniform_type_ACSBuffer_counter Uniform

HLSL Variables and Resources
============================

This section lists how various HLSL variables and resources are mapped.

Variables are defined in HLSL using the following
`syntax <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509706(v=vs.85).aspx>`_
rules::

  [StorageClass] [TypeModifier] Type Name[Index]
      [: Semantic]
      [: Packoffset]
      [: Register];
      [Annotations]
      [= InitialValue]

Storage class
-------------

Normal local variables (without any modifier) will be placed in the ``Function``
SPIR-V storage class.

``static``
~~~~~~~~~~

- Global variables with ``static`` modifier will be placed in the ``Private``
  SPIR-V storage class. Initalizers of such global variables will be translated
  into SPIR-V ``OpVariable`` initializers if possible; otherwise, they will be
  initialized at the very beginning of the `entry function wrapper`_ using
  SPIR-V ``OpStore``.
- Local variables with ``static`` modifier will also be placed in the
  ``Private`` SPIR-V storage class. initializers of such local variables will
  also be translated into SPIR-V ``OpVariable`` initializers if possible;
  otherwise, they will be initialized at the very beginning of the enclosing
  function. To make sure that such a local variable is only initialized once,
  a second boolean variable of the ``Private`` SPIR-V storage class will be
  generated to mark its initialization status.

Type modifier
-------------

[TODO]

HLSL semantic and Vulkan ``Location``
------------------------------------

Direct3D uses HLSL "`semantics <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509647(v=vs.85).aspx>`_"
to compose and match the interfaces between subsequent stages. These semantic
strings can appear after struct members, function parameters and return
values. E.g.,

.. code:: hlsl

  struct VSInput {
    float4 pos  : POSITION;
    float3 norm : NORMAL;
  };

  float4 VSMain(in  VSInput input,
                in  float4  tex   : TEXCOORD,
                out float4  pos   : SV_Position) : TEXCOORD {
    pos = input.pos;
    return tex;
  }

In contrary, Vulkan stage input and output interface matching is via explicit
``Location`` numbers. Details can be found `here <https://www.khronos.org/registry/vulkan/specs/1.0-wsi_extensions/html/vkspec.html#interfaces-iointerfaces>`_.

To translate HLSL to SPIR-V for Vulkan, semantic strings need to be mapped to
Vulkan ``Location`` numbers properly. This can be done either explicitly via
information provided by the developer or implicitly by the compiler.

Explicit ``Location`` number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``[[vk::location(X)]]`` can be attached to the entities where semantic are
allowed to attach (struct fields, function parameters, and function returns).
For the above exmaple we can have:

.. code:: hlsl

  struct VSInput {
    [[vk::location(0)]] float4 pos  : POSITION;
    [[vk::location(1)]] float3 norm : NORMAL;
  };

  [[vk::location(1)]]
  float4 VSMain(in  VSInput input,
                [[vk::location(2)]]
                in  float4  tex     : TEXCOORD,
                out float4  pos     : SV_Position) : TEXCOORD {
    pos = input.pos;
    return tex;
  }

In the above, input ``POSITION``, ``NORMAL``, and ``TEXCOORD`` will be mapped to
``Location`` 0, 1, and 2, respectively, and output ``TEXCOORD`` will be mapped
to ``Location`` 1.

[TODO] Another explicit way: using command-line options

Please note that the compiler prohibits mixing the explicit and implicit
approach for the same SigPoint to avoid complexity and fallibility. However,
for a certain shader stage, one SigPoint using the explicit approach while the
other adopting the implicit approach is permitted.

Implicit ``Location`` number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Without hints from the developer, the compiler will try its best to map
semantics to ``Location`` numbers. However, there is no single rule for this
mapping; semantic strings should be handled case by case.

Firstly, under certain `SigPoints <https://github.com/Microsoft/DirectXShaderCompiler/blob/master/docs/DXIL.rst#hlsl-signatures-and-semantics>`_,
some system-value (SV) semantic strings will be translated into SPIR-V
``BuiltIn`` decorations:

+----------------------+----------+------------------------+-----------------------+
| HLSL Semantic        | SigPoint | SPIR-V ``BuiltIn``     | SPIR-V Execution Mode |
+======================+==========+========================+=======================+
|                      | VSOut    | ``Position``           | N/A                   |
| SV_Position          +----------+------------------------+-----------------------+
|                      | PSIn     | ``FragCoord``          | N/A                   |
+----------------------+----------+------------------------+-----------------------+
| SV_VertexID          | VSIn     | ``VertexIndex``        | N/A                   |
+----------------------+----------+------------------------+-----------------------+
| SV_InstanceID        | VSIn     | ``InstanceIndex``      | N/A                   |
+----------------------+----------+------------------------+-----------------------+
| SV_Depth             | PSOut    | ``FragDepth``          | N/A                   |
+----------------------+----------+------------------------+-----------------------+
| SV_DepthGreaterEqual | PSOut    | ``FragDepth``          | ``DepthGreater``      |
+----------------------+----------+------------------------+-----------------------+
| SV_DepthLessEqual    | PSOut    | ``FragDepth``          | ``DepthLess``         |
+----------------------+----------+------------------------+-----------------------+
| SV_DispatchThreadID  | CSIn     | ``GlobalInvocationId`` | N/A                   |
+----------------------+----------+------------------------+-----------------------+

[TODO] add other SV semantic strings in the above

For entities (function parameters, function return values, struct fields) with
the above SV semantic strings attached, SPIR-V variables of the
``Input``/``Output`` storage class will be created. They will have the
corresponding SPIR-V ``Builtin``  decorations according to the above table.

SV semantic strings not translated into SPIR-V ``BuiltIn`` decorations will be
handled similarly as non-SV (arbitrary) semantic strings: a SPIR-V variable
of the ``Input``/``Output`` storage class will be created for each entity with
such semantic string. Then sort all semantic strings according to declaration
(the default, or if ``-fvk-stage-io-order=decl`` is given) or alphabetical
(if ``-fvk-stage-io-order=alpha`` is given) order, and assign ``Location``
numbers sequentially to the corresponding SPIR-V variables. Note that this means
flattening all structs if structs are used as function parameters or returns.

There is an exception to the above rule for SV_Target[N]. It will always be
mapped to ``Location`` number N.

HLSL register and Vulkan binding
--------------------------------

In shaders for DirectX, resources are accessed via registers; while in shaders
for Vulkan, it is done via descriptor set and binding numbers. The developer
can explicitly annotate variables in HLSL to specify descriptor set and binding
numbers, or leave it to the compiler to derive implicitly from registers.
The explicit way has precedence over the implicit way. However, a mix of both
way is not allowed (yet).

Explicit binding number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``[[vk::binding(X[, Y])]]`` can be attached to global variables to specify the
descriptor set ``Y`` and binding ``X``. The descriptor set number is optional;
if missing, it will be zero.

Implicit binding number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Without explicit annotations, the compiler will try to deduce descriptor set and
binding numbers in the following way:

If there is ``:register(xX, spaceY)`` specified for the given global variable,
the corresponding resource will be assigned to descriptor set ``Y`` and binding
number ``X``, regardless the resource type ``x``. (Note that this can cause
reassignment of the same set and binding number pair. [TODO])

If there is no register specification, the corresponding resource will be
assigned to the next available binding number, starting from 0, in descriptor
set #0.

HLSL Expressions
================

Unless explicitly noted, matrix per-element operations will be conducted on
each component vector and then collected into the result matrix. The following
sections lists the SPIR-V opcodes for scalars and vectors.

Arithmetic operators
--------------------

`Arithmetic operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Additive_and_Multiplicative_Operators>`_
(``+``, ``-``, ``*``, ``/``, ``%``) are translated into their corresponding
SPIR-V opcodes according to the following table.

+-------+-----------------------------+-------------------------------+--------------------+
|       | (Vector of) Signed Integers | (Vector of) Unsigned Integers | (Vector of) Floats |
+=======+=============================+===============================+====================+
| ``+`` |                         ``OpIAdd``                          |     ``OpFAdd``     |
+-------+-------------------------------------------------------------+--------------------+
| ``-`` |                         ``OpISub``                          |     ``OpFSub``     |
+-------+-------------------------------------------------------------+--------------------+
| ``*`` |                         ``OpIMul``                          |     ``OpFMul``     |
+-------+-----------------------------+-------------------------------+--------------------+
| ``/`` |    ``OpSDiv``               |       ``OpUDiv``              |     ``OpFDiv``     |
+-------+-----------------------------+-------------------------------+--------------------+
| ``%`` |    ``OpSRem``               |       ``OpUMod``              |     ``OpFRem``     |
+-------+-----------------------------+-------------------------------+--------------------+

Note that for modulo operation, SPIR-V has two sets of instructions: ``Op*Rem``
and ``Op*Mod``. For ``Op*Rem``, the sign of a non-0 result comes from the first
operand; while for ``Op*Mod``, the sign of a non-0 result comes from the second
operand. HLSL doc does not mandate which set of instructions modulo operations
should be translated into; it only says "the % operator is defined only in cases
where either both sides are positive or both sides are negative." So technically
it's undefined behavior to use the modulo operation with operands of different
signs. But considering HLSL's C heritage and the behavior of Clang frontend, we
translate modulo operators into ``Op*Rem`` (there is no ``OpURem``).

For multiplications of float vectors and float scalars, the dedicated SPIR-V
operation ``OpVectorTimesScalar`` will be used. Similarly, for multiplications
of float matrices and float scalars, ``OpMatrixTimesScalar`` will be generated.

Bitwise operators
-----------------

`Bitwise operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Bitwise_Operators>`_
(``~``, ``&``, ``|``, ``^``, ``<<``, ``>>``) are translated into their
corresponding SPIR-V opcodes according to the following table.

+--------+-----------------------------+-------------------------------+
|        | (Vector of) Signed Integers | (Vector of) Unsigned Integers |
+========+=============================+===============================+
| ``~``  |                         ``OpNot``                           |
+--------+-------------------------------------------------------------+
| ``&``  |                      ``OpBitwiseAnd``                       |
+--------+-------------------------------------------------------------+
| ``|``  |                      ``OpBitwiseOr``                        |
+--------+-----------------------------+-------------------------------+
| ``^``  |                      ``OpBitwiseXor``                       |
+--------+-----------------------------+-------------------------------+
| ``<<`` |                   ``OpShiftLeftLogical``                    |
+--------+-----------------------------+-------------------------------+
| ``>>`` | ``OpShiftRightArithmetic``  | ``OpShiftRightLogical``       |
+--------+-----------------------------+-------------------------------+

Comparison operators
--------------------

`Comparison operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Comparison_Operators>`_
(``<``, ``<=``, ``>``, ``>=``, ``==``, ``!=``) are translated into their
corresponding SPIR-V opcodes according to the following table.

+--------+-----------------------------+-------------------------------+------------------------------+
|        | (Vector of) Signed Integers | (Vector of) Unsigned Integers |     (Vector of) Floats       |
+========+=============================+===============================+==============================+
| ``<``  |  ``OpSLessThan``            |  ``OpULessThan``              |  ``OpFOrdLessThan``          |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``<=`` |  ``OpSLessThanEqual``       |  ``OpULessThanEqual``         |  ``OpFOrdLessThanEqual``     |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``>``  |  ``OpSGreaterThan``         |  ``OpUGreaterThan``           |  ``OpFOrdGreaterThan``       |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``>=`` |  ``OpSGreaterThanEqual``    |  ``OpUGreaterThanEqual``      |  ``OpFOrdGreaterThanEqual``  |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``==`` |                     ``OpIEqual``                            |  ``OpFOrdEqual``             |
+--------+-------------------------------------------------------------+------------------------------+
| ``!=`` |                     ``OpINotEqual``                         |  ``OpFOrdNotEqual``          |
+--------+-------------------------------------------------------------+------------------------------+

Note that for comparison of (vectors of) floats, SPIR-V has two sets of
instructions: ``OpFOrd*``, ``OpFUnord*``. We translate into ``OpFOrd*`` ones.

Boolean math operators
----------------------

`Boolean match operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Boolean_Math_Operators>`_
(``&&``, ``||``, ``?:``) are translated into their corresponding SPIR-V opcodes
according to the following table.

+--------+----------------------+
|        | (Vector of) Booleans |
+========+======================+
| ``&&`` |  ``OpLogicalAnd``    |
+--------+----------------------+
| ``||`` |  ``OpLogicalOr``     |
+--------+----------------------+
| ``?:`` |  ``OpSelect``        |
+--------+----------------------+

Please note that "unlike short-circuit evaluation of ``&&``, ``||``, and ``?:``
in C, HLSL expressions never short-circuit an evaluation because they are vector
operations. All sides of the expression are always evaluated."

Unary operators
---------------

For `unary operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Unary_Operators>`_:

- ``!`` is translated into ``OpLogicalNot``. Parsing will gurantee the operands
  are of boolean types by inserting necessary casts.
- ``+`` requires no additional SPIR-V instructions.
- ``-`` is translated into ``OpSNegate`` and ``OpFNegate`` for (vectors of)
  integers and floats, respectively.

Casts
-----

Casting between (vectors) of scalar types is translated according to the following table:

+------------+-------------------+-------------------+-------------------+-------------------+
| From \\ To |        Bool       |       SInt        |      UInt         |       Float       |
+============+===================+===================+===================+===================+
|   Bool     |       no-op       |                 select between one and zero               |
+------------+-------------------+-------------------+-------------------+-------------------+
|   SInt     |                   |     no-op         |  ``OpBitcast``    | ``OpConvertSToF`` |
+------------+                   +-------------------+-------------------+-------------------+
|   UInt     | compare with zero |   ``OpBitcast``   |      no-op        | ``OpConvertUToF`` |
+------------+                   +-------------------+-------------------+-------------------+
|   Float    |                   | ``OpConvertFToS`` | ``OpConvertFToU`` |      no-op        |
+------------+-------------------+-------------------+-------------------+-------------------+

Indexing operator
-----------------

The ``[]`` operator can also be used to access elements in a matrix or vector.
A matrix whose row and/or column count is 1 will be translated into a vector or
scalar. If a variable is used as the index for the dimension whose count is 1,
that variable will be ignored in the generated SPIR-V code. This is because
out-of-bound indexing triggers undefined behavior anyway. For example, for a
1xN matrix ``mat``, ``mat[index][0]`` will be translated into
``OpAccessChain ... %mat %uint_0``. Similarly, variable index into a size 1
vector will also be ignored and the only element will be always returned.

HLSL Control Flows
==================

This section lists how various HLSL control flows are mapped.

Switch statement
----------------

HLSL `switch statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509669(v=vs.85).aspx>`_
are translated into SPIR-V using:

- **OpSwitch**: if (all case values are integer literals or constant integer
  variables) and (no attribute or the ``forcecase`` attribute is specified)
- **A series of if statements**: for all other scenarios (e.g., when
  ``flatten``, ``branch``, or ``call`` attribute is specified)

Loops (for, while, do)
----------------------

HLSL `for statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509602(v=vs.85).aspx>`_,
`while statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509708(v=vs.85).aspx>`_,
and `do statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509593(v=vs.85).aspx>`_
are translated into SPIR-V by constructing all necessary basic blocks and using
``OpLoopMerge`` to organize as structured loops.

The HLSL attributes for these statements are translated into SPIR-V loop control
masks according to the following table:

+-------------------------+--------------------------------------------------+
|   HLSL loop attribute   |            SPIR-V Loop Control Mask              |
+=========================+==================================================+
|        ``unroll(x)``    |                ``Unroll``                        |
+-------------------------+--------------------------------------------------+
|         ``loop``        |              ``DontUnroll``                      |
+-------------------------+--------------------------------------------------+
|        ``fastopt``      |              ``DontUnroll``                      |
+-------------------------+--------------------------------------------------+
| ``allow_uav_condition`` |           Currently Unimplemented                |
+-------------------------+--------------------------------------------------+

HLSL Functions
==============

All functions reachable from the entry-point function will be translated into
SPIR-V code. Functions not reachable from the entry-point function will be
ignored.

Entry function wrapper
----------------------

HLSL entry functions takes in parameters and returns values. These parameters
and return values can have semantics attached or if they are struct type,
the struct fields can have semantics attached. However, in Vulkan, the entry
function must be of the ``void(void)`` signature. To handle this difference,
for a given entry function ``main``, we will emit a wrapper function for it.

The wrapper function will take the name of the source code entry function,
while the source code entry function will have its name prefixed with "src.".
The wrapper function reads in stage input/builtin variables created according
to semantics and groups them into composites meeting the requirements of the
source code entry point. Then the wrapper calls the source code entry point.
The return value is extracted and components of it will be written to stage
output/builtin variables created according to semantics. For example:


.. code:: hlsl

  // HLSL source code

  struct S {
    bool a : A;
    uint2 b: B;
    float2x3 c: C;
  };

  struct T {
    S x;
    int y: D;
  };

  T main(T input) {
    return input;
  }


.. code:: spirv

  ; SPIR-V code

  %in_var_A = OpVariable %_ptr_Input_bool Input
  %in_var_B = OpVariable %_ptr_Input_v2uint Input
  %in_var_C = OpVariable %_ptr_Input_mat2v3float Input
  %in_var_D = OpVariable %_ptr_Input_int Input

  %out_var_A = OpVariable %_ptr_Output_bool Output
  %out_var_B = OpVariable %_ptr_Output_v2uint Output
  %out_var_C = OpVariable %_ptr_Output_mat2v3float Output
  %out_var_D = OpVariable %_ptr_Output_int Output

  ; Wrapper function starts

  %main    = OpFunction %void None {{%\d+}}
  {{%\d+}} = OpLabel

  %param_var_input = OpVariable %_ptr_Function_T Function

  ; Load stage input variables and group into the expected composite

  [[inA:%\d+]]     = OpLoad %bool %in_var_A
  [[inB:%\d+]]     = OpLoad %v2uint %in_var_B
  [[inC:%\d+]]     = OpLoad %mat2v3float %in_var_C
  [[inS:%\d+]]     = OpCompositeConstruct %S [[inA]] [[inB]] [[inC]]
  [[inD:%\d+]]     = OpLoad %int %in_var_D
  [[inT:%\d+]]     = OpCompositeConstruct %T [[inS]] [[inD]]
                     OpStore %param_var_input [[inT]]

  [[ret:%\d+]]  = OpFunctionCall %T %src_main %param_var_input

  ; Extract component values from the composite and store into stage output variables

  [[outS:%\d+]] = OpCompositeExtract %S [[ret]] 0
  [[outA:%\d+]] = OpCompositeExtract %bool [[outS]] 0
                  OpStore %out_var_A [[outA]]
  [[outB:%\d+]] = OpCompositeExtract %v2uint [[outS]] 1
                  OpStore %out_var_B [[outB]]
  [[outC:%\d+]] = OpCompositeExtract %mat2v3float [[outS]] 2
                  OpStore %out_var_C [[outC]]
  [[outD:%\d+]] = OpCompositeExtract %int [[ret]] 1
                  OpStore %out_var_D [[outD]]

  OpReturn
  OpFunctionEnd

  ; Source code entry point starts

  %src_main = OpFunction %T None ...

In this way, we can concentrate all stage input/output/builtin variable
manipulation in the wrapper function and handle the source code entry function
just like other nomal functions.

Function parameter
------------------

For a function ``f`` which has a parameter of type ``T``, the generated SPIR-V
signature will use type ``T*`` for the parameter. At every call site of ``f``,
additional local variables will be allocated to hold the actual arguments.
The local variables are passed in as direct function arguments. For example:

.. code:: hlsl

  // HLSL source code

  float4 f(float a, int b) { ... }

  void caller(...) {
    ...
    float4 result = f(...);
    ...
  }

.. code:: spirv

  ; SPIR-V code

                ...
  %i32PtrType = OpTypePointer Function %int
  %f32PtrType = OpTypePointer Function %float
      %fnType = OpTypeFunction %v4float %f32PtrType %i32PtrType
                ...

           %f = OpFunction %v4float None %fnType
           %a = OpFunctionParameter %f32PtrType
           %b = OpFunctionParameter %i32PtrType
                ...

      %caller = OpFunction ...
                ...
     %aAlloca = OpVariable %_ptr_Function_float Function
     %bAlloca = OpVariable %_ptr_Function_int Function
                ...
                OpStore %aAlloca ...
                OpStore %bAlloca ...
      %result = OpFunctioncall %v4float %f %aAlloca %bAlloca
                ...

This approach gives us unified handling of function parameters and local
variables: both of them are accessed via load/store instructions.

Intrinsic functions
-------------------

The following intrinsic HLSL functions are currently supported:

- ``dot`` : performs dot product of two vectors, each containing floats or
  integers. If the two parameters are vectors of floats, we use SPIR-V's
  ``OpDot`` instruction to perform the translation. If the two parameters are
  vectors of integers, we multiply corresponding vector elementes using
  ``OpIMul`` and accumulate the results using ``OpIAdd`` to compute the dot
  product.
- ``mul``: performs multiplications. Each argument may be a scalar, vector,
  or matrix. Depending on the argument type, this will be translated into
  one of the multiplication instructions.
- ``all``: returns true if all components of the given scalar, vector, or
  matrix are true. Performs conversions to boolean where necessary. Uses SPIR-V
  ``OpAll`` for scalar arguments and vector arguments. For matrix arguments,
  performs ``OpAll`` on each row, and then again on the vector containing the
  results of all rows.
- ``any``: returns true if any component of the given scalar, vector, or matrix
  is true. Performs conversions to boolean where necessary. Uses SPIR-V
  ``OpAny`` for scalar arguments and vector arguments. For matrix arguments,
  performs ``OpAny`` on each row, and then again on the vector containing the
  results of all rows.
- ``asfloat``: converts the component type of a scalar/vector/matrix from float,
  uint, or int into float. Uses ``OpBitcast``. This method currently does not
  support taking non-float matrix arguments.
- ``asint``: converts the component type of a scalar/vector/matrix from float or
  uint into int. Uses ``OpBitcast``. This method currently does not support
  conversion into integer matrices.
- ``asuint``: converts the component type of a scalar/vector/matrix from float
  or int into uint. Uses ``OpBitcast``. This method currently does not support
  conversion into unsigned integer matrices.

Using GLSL extended instructions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

the following intrinsic HLSL functions are translated using their equivalent
instruction in the `GLSL extended instruction set <https://www.khronos.org/registry/spir-v/specs/1.0/GLSL.std.450.html>`_.

======================= ===============================
HLSL Intrinsic Function   GLSL Extended Instruction
======================= ===============================
``abs``                 ``SAbs``/``FAbs``
``acos``                ``Acos``
``asin``                ``Asin``
``atan``                ``Atan``
``ceil``                ``Ceil``
``clamp``               ``SClamp``/``UClamp``/``FClamp``
``cos``                 ``Cos``
``cosh``                ``Cosh``
``cross``                ``Cross``
``degrees``             ``Degrees``
``radians``             ``Radian``
``determinant``         ``Determinant``
``exp``                 ``Exp``
``exp2``                ``exp2``
``floor``               ``Floor``
``length``              ``Length``
``log``                 ``Log``
``log2``                ``Log2``
``max``                 ``SMax``/``UMax``/``FMax``
``min``                 ``SMin``/``UMin``/``FMin``
``normalize``           ``Normalize``
``pow``                 ``Pow``
``reflect``             ``Reflect``
``round``               ``Round``
``rsqrt``               ``InverseSqrt``
``step``                ``Step``
``sign``                ``SSign``/``FSign``
``sin``                 ``Sin``
``sinh``                ``Sinh``
``tan``                 ``Tan``
``tanh``                ``Tanh``
``sqrt``                ``Sqrt``
``trunc``               ``Trunc``
======================= ===============================
