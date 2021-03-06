// Run: %dxc -T ps_6_0 -E main

// CHECK:      OpDecorate %sampler1 DescriptorSet 0
// CHECK-NEXT: OpDecorate %sampler1 Binding 1
SamplerState sampler1: register(s1);

// CHECK:      OpDecorate %sampler2 DescriptorSet 1
// CHECK-NEXT: OpDecorate %sampler2 Binding 2
SamplerState sampler2 : register(s2, space1);

// Note: overlapping set # and binding # for now.
// CHECK:      OpDecorate %texture1 DescriptorSet 1
// CHECK-NEXT: OpDecorate %texture1 Binding 2
Texture2D<float4> texture1: register(t2, space1);

// Note: overlapping set # and binding # for now.
// CHECK:      OpDecorate %texture2 DescriptorSet 0
// CHECK-NEXT: OpDecorate %texture2 Binding 1
Texture3D<float4> texture2: register(t1);

// Note: using the next available binding #
// CHECK:      OpDecorate %sampler3 DescriptorSet 0
// CHECK-NEXT: OpDecorate %sampler3 Binding 0
SamplerState sampler3;

// Note: using the next available binding #
// CHECK:      OpDecorate %sampler4 DescriptorSet 0
// CHECK-NEXT: OpDecorate %sampler4 Binding 2
SamplerState sampler4;

// CHECK:      OpDecorate %var_myCbuffer DescriptorSet 3
// CHECK-NEXT: OpDecorate %var_myCbuffer Binding 1
cbuffer myCbuffer : register(b1, space3) {
    float4 stuff;
}

// CHECK:      OpDecorate %myBuffer DescriptorSet 0
// CHECK-NEXT: OpDecorate %myBuffer Binding 3
Buffer<int> myBuffer : register(t3, space0);

// CHECK: OpDecorate %myRWBuffer DescriptorSet 1
// CHECK-NEXT: OpDecorate %myRWBuffer Binding 4
RWBuffer<float4> myRWBuffer : register(u4, space1);

struct S {
    float4 f;
};

// CHECK:      OpDecorate %myCbuffer2 DescriptorSet 2
// CHECK-NEXT: OpDecorate %myCbuffer2 Binding 2
ConstantBuffer<S> myCbuffer2 : register(b2, space2);

// CHECK:      OpDecorate %myCbuffer3 DescriptorSet 3
// CHECK-NEXT: OpDecorate %myCbuffer3 Binding 2
ConstantBuffer<S> myCbuffer3 : register(b2, space3);

// CHECK:      OpDecorate %sbuffer1 DescriptorSet 0
// CHECK-NEXT: OpDecorate %sbuffer1 Binding 5
  StructuredBuffer<S> sbuffer1 : register(t5);
// CHECK:      OpDecorate %sbuffer2 DescriptorSet 1
// CHECK-NEXT: OpDecorate %sbuffer2 Binding 6
RWStructuredBuffer<S> sbuffer2 : register(u6, space1);

    // The counter variable will use the next unassigned number
// CHECK:      OpDecorate %abuffer DescriptorSet 0
// CHECK-NEXT: OpDecorate %abuffer Binding 5
// CHECK-NEXT: OpDecorate %counter_var_abuffer DescriptorSet 0
// CHECK-NEXT: OpDecorate %counter_var_abuffer Binding 4
AppendStructuredBuffer<S> abuffer : register(u5);

    // The counter variable will use the next unassigned number
// CHECK:      OpDecorate %csbuffer DescriptorSet 0
// CHECK-NEXT: OpDecorate %csbuffer Binding 7
// CHECK-NEXT: OpDecorate %counter_var_csbuffer DescriptorSet 0
// CHECK-NEXT: OpDecorate %counter_var_csbuffer Binding 6
ConsumeStructuredBuffer<S> csbuffer : register(u7);

float4 main() : SV_Target {
    return 1.0;
}
