//
//  ParallelCoordinateHoughTransform.metal
//  AccessibleVideo
//
//  Created by Jamie Scanlon on 5/18/16.
//  Copyright © 2016 Tenth Letter Made LLC. All rights reserved.
//

#include <metal_stdlib>
#include "Common.metal"
using namespace metal;

kernel void ParallelCoordinateHoughTransform(texture2d<float, access::read> inTexture [[texture(0)]],
                                             texture2d<float, access::write> outTableT [[texture(1)]],
                                             texture2d<float, access::write> outTableS [[texture(2)]],
                                             device MinMaxPoint *minmaxPoint [[buffer(0)]],
                                             uint2 gid [[thread_position_in_grid]]) {
    
    float xCoordinate = static_cast<float>(gid.x);
    float yCoordinate = static_cast<float>(gid.y);
    
    float normalizedXCoordinate = (-1.0 + 2.0 * (xCoordinate / 4) / inTexture.get_width());
    float normalizedYCoordinate = (-1.0 + 2.0 * (yCoordinate) / inTexture.get_height());
    
    minmaxPoint->minX = min(minmaxPoint->minX, normalizedXCoordinate);
    minmaxPoint->minY = min(minmaxPoint->minY, normalizedYCoordinate);
    minmaxPoint->maxX = max(minmaxPoint->maxX, normalizedXCoordinate);
    minmaxPoint->maxY = max(minmaxPoint->maxY, normalizedYCoordinate);
    
    outTableT.write(float4(-1.0, -normalizedYCoordinate, 0.0, normalizedXCoordinate), gid); // T space coordinates, (-d, -y) to (0, x)
    outTableS.write(float4(0.0, normalizedXCoordinate, 1.0, normalizedYCoordinate), gid); // S space coordinates, (0, x) to (d, y)
    
}
