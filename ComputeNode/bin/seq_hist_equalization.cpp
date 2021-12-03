#include <cmath>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "rgbhsv.h"

#define COLORDEPTH 256

void histogram_equalization(unsigned char *, long);

int main(int argc, char *argv[]){
    printf("Input parameters:\n%s\n%s\n%s\n\n", argv[0], argv[1], argv[2]);
    int width, height, channel_num;

    // read the image
    unsigned char *rgb_image = stbi_load(argv[1], &width, &height, &channel_num, 0);

    long pixel_num = width * height;
    printf("Width:%d, Height:%d, Channel_num:%d\n\n", width, height, channel_num);

    if (channel_num > 2) {
        hsv *hsv_image;
        hsv_image = (hsv*) malloc (pixel_num*sizeof(hsv));
        unsigned char *brightness_image;
        brightness_image = (unsigned char *) malloc (pixel_num*sizeof(unsigned char));
        
        for (long i=0; i<pixel_num; i++) {
            rgb pixelRGB = {(double)rgb_image[i*channel_num] / 255, (double)rgb_image[i*channel_num+1] / 255, (double)rgb_image[i*channel_num+2] / 255};
            hsv_image[i] = rgb2hsv(pixelRGB);
            brightness_image[i] = round(hsv_image[i].v*255);
        }

        
        histogram_equalization(brightness_image, pixel_num);
        
        for (long i=0; i<pixel_num; i++) {
            hsv_image[i].v = (double)brightness_image[i] / 255;
            rgb pixelRGB = hsv2rgb(hsv_image[i]);
            rgb_image[i*channel_num] = pixelRGB.r * 255;
            rgb_image[i*channel_num+1] = pixelRGB.g * 255;
            rgb_image[i*channel_num+2] = pixelRGB.b * 255;
        }
        free(hsv_image);
        free(brightness_image);
    } else if (channel_num == 2) {
        unsigned char *brightness_image;
        brightness_image = (unsigned char *) malloc (pixel_num*sizeof(unsigned char));
        for (long i=0; i<pixel_num; i++) {
            brightness_image[i] = rgb_image[i*2];
        }

        histogram_equalization(brightness_image, pixel_num);

        for (long i=0; i<pixel_num; i++) {
            rgb_image[i*2] = brightness_image[i];
        }
        free(brightness_image);
    } else {
        histogram_equalization(rgb_image, pixel_num);
    }
    
    // write the image
    if (argc == 4 && strcmp(argv[3], "png")==0){
        stbi_write_png(argv[2], width, height, channel_num, rgb_image, width*channel_num);
    } else {
        stbi_write_jpg(argv[2], width, height, channel_num, rgb_image, 100);
    }
    printf("Processing is finished!\n");

    stbi_image_free(rgb_image);

    return 0;
}

void histogram_equalization(unsigned char *image, long pixel_num) {
    // initialize histogram array and transform array
    int counter_array[COLORDEPTH], trans_table[COLORDEPTH];
    for (int i=0; i<COLORDEPTH; i++) {
        counter_array[i] = 0;
    }

    // calculate histogram
    for (int i=0; i<pixel_num; i++) {
        counter_array[image[i]]++;
    }

    // build transform function
    long frequency_sum = 0;
    for (int i=0; i<COLORDEPTH; i++) {
        frequency_sum += counter_array[i];
        trans_table[i] = round((double)frequency_sum / (double)pixel_num * COLORDEPTH);
    }

    // transform image
    for (int i=0; i<pixel_num; i++) {
        image[i] = trans_table[image[i]];
    }
}