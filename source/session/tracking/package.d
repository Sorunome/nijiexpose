/*
    Copyright © 2022, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module session.tracking;
import session.tracking.expr;
import session.tracking.vspace;
import session.scene;
import inochi2d;
import inochi2d.math.serialization;
import fghj;

/**
    Binding Type
*/
enum BindingType {
    /**
        A binding where the base source is blended via
        in/out ratios
    */
    RatioBinding,

    /**
        A binding in which math expressions are used to
        blend between the sources in the VirtualSpace zone.
    */
    ExpressionBinding,

    /**
        Binding controlled from an external source.
        Eg. over the internet or from a plugin.
    */
    External
}

/**
    Source type
*/
enum SourceType {
    /**
        The source is a blendshape
    */
    Blendshape,

    /**
        Source is the X position of a bone
    */
    BonePosX,

    /**
        Source is the Y position of a bone
    */
    BonePosY,

    /**
        Source is the Y position of a bone
    */
    BonePosZ,

    /**
        Source is the roll of a bone
    */
    BoneRotRoll,

    /**
        Source is the pitch of a bone
    */
    BoneRotPitch,

    /**
        Source is the yaw of a bone
    */
    BoneRotYaw,
}

/**
    Tracking Binding 
*/
class TrackingBinding {
private:
    // UUID of param to map to
    uint paramUUID;

    // Sum of weighted plugin values
    float sum = 0;

    // Combined value of weights
    float weights = 0;

    /**
        Maps an input value to an offset (0.0->1.0)
    */
    float mapValue(float value, float min, float max) {
        float range = max - min;
        float tmp = (value - min);
        float off = tmp / range;
        return clamp(off, 0, 1);
    }

    /**
        Maps an offset (0.0->1.0) to a value
    */
    float unmapValue(float offset, float min, float max) {
        float range = max - min;
        return (range * offset) + min;
    }

public:
    /**
        Display name for the binding
    */
    string name;

    /**
        Name of the source blendshape or bone
    */
    string sourceName;

    /**
        Display Name of the source blendshape or bone
    */
    string sourceDisplayName;

    /**
        The type of the binding
    */
    BindingType type;

    /**
        The type of the tracking source
    */
    SourceType sourceType;

    /**
        The Inochi2D parameter it should apply to
    */
    Parameter param;

    /**
        Expression (if in ExpressionBinding mode)
    */
    Expression expr;

    /// Ratio for input
    vec2 inRange;

    /// Ratio for output
    vec2 outRange;

    /// Last input value
    float inVal = 0;

    /// Last output value
    float outVal = 0;

    /**
        Weights the user has set for each plugin
    */
    float[string] pluginWeights;

    /**
        The axis to apply the binding to
    */
    int axis;

    /**
        Dampening level
    */
    int dampenLevel;

    /**
        Whether to inverse the binding
    */
    bool inverse;

    void serialize(S)(ref S serializer) {
        auto state = serializer.objectBegin;
            serializer.putKey("name");
            serializer.putValue(name);
            serializer.putKey("sourceName");
            serializer.putValue(sourceName);
            serializer.putKey("sourceType");
            serializer.serializeValue(sourceType);
            serializer.putKey("bindingType");
            serializer.serializeValue(type);
            serializer.putKey("param");
            serializer.serializeValue(param.uuid);

            switch(type) {
                case BindingType.RatioBinding:
                    serializer.putKey("axis");
                    serializer.putValue(axis);
                    serializer.putKey("dampenLevel");
                    serializer.putValue(dampenLevel);
                    serializer.putKey("inverse");
                    serializer.putValue(inverse);

                    serializer.putKey("inRange");
                    inRange.serialize(serializer);
                    serializer.putKey("outRange");
                    outRange.serialize(serializer);
                    break;
                case BindingType.ExpressionBinding:
                    serializer.putKey("signature");
                    serializer.putValue(expr.signature());
                    serializer.putKey("expression");
                    serializer.putValue(expr.expression());
                    break;
                default: break;
            }

        serializer.objectEnd(state);
    }
    
    SerdeException deserializeFromFghj(Fghj data) {
        data["name"].deserializeValue(name);
        data["sourceName"].deserializeValue(sourceName);
        data["sourceType"].deserializeValue(sourceType);
        data["bindingType"].deserializeValue(type);
        data["param"].deserializeValue(paramUUID);

        switch(type) {
            case BindingType.RatioBinding:
                data["axis"].deserializeValue(axis);
                data["dampenLevel"].deserializeValue(dampenLevel);
                data["inverse"].deserializeValue(inverse);
                inRange.deserialize(data["inRange"]);
                outRange.deserialize(data["outRange"]);
                break;
            case BindingType.ExpressionBinding:
                string exprSig;
                string exprStr;
                data["signature"].deserializeValue(exprSig);
                data["expression"].deserializeValue(exprStr);
                expr = Expression(exprSig, exprStr);
                break;
            default: break;
        }
        
        return null;
    }

    /**
        Finalizes the tracking binding
    */
    void finalize(ref Puppet puppet) {
        param = puppet.findParameter(paramUUID);
    }

    /**
        Updates the parameter binding
    */
    void update() {
        param.value.vector[axis] = 0;
        sum = 0;

        switch(type) {
            case BindingType.RatioBinding:
                if (sourceName.length == 0) break;

                float src = 0;

                switch(sourceType) {

                    case SourceType.Blendshape:
                        src = insScene.space.currentZone.getBlendshapeFor(sourceName);
                        break;

                    case SourceType.BonePosX:
                        src = insScene.space.currentZone.getBoneFor(sourceName).position.x;
                        break;

                    case SourceType.BonePosY:
                        src = insScene.space.currentZone.getBoneFor(sourceName).position.y;
                        break;

                    case SourceType.BonePosZ:
                        src = insScene.space.currentZone.getBoneFor(sourceName).position.z;
                        break;

                    case SourceType.BoneRotRoll:
                        src = insScene.space.currentZone.getBoneFor(sourceName).rotation.roll.degrees;
                        break;

                    case SourceType.BoneRotPitch:
                        src = insScene.space.currentZone.getBoneFor(sourceName).rotation.pitch.degrees;
                        break;

                    case SourceType.BoneRotYaw:
                        src = insScene.space.currentZone.getBoneFor(sourceName).rotation.yaw.degrees;
                        break;
                    default: assert(0);
                }

                // Calculate the input ratio (within 0->1)
                float target = mapValue(src, inRange.x, inRange.y);
                if (inverse) target = 1f-target;

                // NOTE: Dampen level of 0 = no damping
                // Dampen level 1-10 is inverse due to the dampen function taking *speed* as a value.
                if (dampenLevel == 0) inVal = target;
                else inVal = dampen(inVal, target, deltaTime(), cast(float)(11-dampenLevel));
                
                // Calculate the output ratio (whatever outRange is)
                outVal = unmapValue(inVal, outRange.x, outRange.y);
                param.value.vector[axis] += param.unmapAxis(axis, outVal);
                break;

            case BindingType.ExpressionBinding:
                param.value.vector[axis] += expr.call();
                break; 

            // External bindings
            default: break;
        }
    }
    
    /**
        Submit value for late update application
    */
    void submit(string plugin, float value) {
        if (plugin !in pluginWeights)
            pluginWeights[plugin] = 1;
        
        sum += value*pluginWeights[plugin];
        weights += pluginWeights[plugin];
    }

    /**
        Apply all the weighted plugin values
    */
    void lateUpdate() {
        param.value.vector[axis] += round(sum / weights);
    }
}