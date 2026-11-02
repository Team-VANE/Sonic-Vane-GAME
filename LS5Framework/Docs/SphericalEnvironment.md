# SphericalEnvironment

Create a ShaderMaterial using `res://LS5Framework/Shaders/SphericalEnvironment.gdshader` and assign an environment image. The shader is exported in the Shared pack. The Spike Strip material provides an existing example.

Defaults produce an opaque, unlit spherical reflection, matching the Spike Strip appearance. The shader also supports orthographic cameras. Each object can use its own ShaderMaterial with independent settings while sharing the shader and textures.

- **Environment:** reflection texture, tint, strength, exposure, Mix/Add/Multiply blending, emission, and mipmap blur.
- **Mapping:** spherical reflection or matcap projection, scale, offset, rotation, scrolling, and vertical flip. Sampling clamps to the image edges.
- **Surface:** Transparency, Cull Mode (Back/Front/Disabled), base texture/color, mesh UV scale/offset, lighting amount, metallic, roughness, and specular. Lighting Amount blends the composited surface between self-lit and scene-lit output.
- **Mask:** optional reflection coverage from a selected texture channel, with inversion. Masks use mesh UVs; environment mapping does not.
- **Fresnel:** optional edge-weighted reflection with adjustable exponent and minimum front-facing coverage.
- **Normal:** optional tangent-space normal mapping affecting both reflection and lighting. Mesh tangents and an OpenGL normal texture are required.

For painted metal, use a base texture, reduce Reflection Strength, enable the mask if needed, and raise Lighting Amount. For additive highlights, select Add and darken the base color. Reflection Blur selects existing mip levels; enable mipmap generation on the environment texture. Roughness controls scene lighting independently.

The effect samples an authored image rather than the live scene. Surface Transparency ranges from 0 (opaque) to 1 (invisible). Alpha blending uses an alpha depth prepass; materials using this shader participate in transparent rendering even at the opaque default. Changing a shared ShaderMaterial affects every object using that material; make it unique before editing one object's appearance.

Cull Mode applies per-material face rejection using FRONT_FACING. The shader renders two-sided geometry internally and discards the selected faces; this is not a hardware back-face optimization. Back is the default.
