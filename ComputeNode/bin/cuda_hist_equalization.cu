#include <cmath>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "rgbhsv.h"

#define CUDA 1  
#define COLORDEPTH 256
#define BLOCKSIZE 0

// C function declaration.
void histogram_equalization(unsigned char *, long, int);

// ------------------- CUDA function decleration for Histogram Equalization -------------------------------
__global__ void cu_pll_hist_eq (unsigned char *rgb_image_g, long pix_num, int *counter_array_g, int block_size) {
	// shared memory for color depth.
	//__shared__ int local_depth_hist[COLORDEPTH];
	int local_depth_hist[COLORDEPTH];
	int tid = blockDim.x * blockIdx.x + threadIdx.x;

	// working on blocks of some size and calculating histogram value for
	// particular size only. Later we will add up these values. 
	for(int j=0; j<COLORDEPTH; j++){
		local_depth_hist[j] = 0;
	}

	for(int k=tid*block_size; k<(tid+1)*block_size && k<pix_num; k++) {
		local_depth_hist[rgb_image_g[k]]++;
	}

	__syncthreads();

	for(int i=0; i<COLORDEPTH; i++)
		atomicAdd(&(counter_array_g[i]), (local_depth_hist[i])); 
	
	__syncthreads();
}

__global__ void histogram_transform (int * counter_array_g, int *transformed_histogram, int pixel_num){
	//int tid = blockDim.x*blockIdx.x + threadIdx.x;
	int tid = threadIdx.x;

	int cumulative_sum = 0;
	for(int i=0;i<tid+1; i++)
		cumulative_sum += counter_array_g[i]; 

	transformed_histogram[tid] = round((double)cumulative_sum/(double)pixel_num * COLORDEPTH);
}

__global__ void transform_image(int *transformed_histogram, unsigned char *final_image, unsigned char *rgb_image_g, int pixel_num){
	int tid = blockDim.x*blockIdx.x + threadIdx.x;

	if(tid < pixel_num)
		final_image[tid] = transformed_histogram[rgb_image_g[tid]] % 256;
}

// --------------- The main function --------------------------- 
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

		
		histogram_equalization(brightness_image, pixel_num, height);
		
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

		histogram_equalization(brightness_image, pixel_num, height);

		for (long i=0; i<pixel_num; i++) {
			rgb_image[i*2] = brightness_image[i];
		}
		free(brightness_image);
	} else {
		histogram_equalization(rgb_image, pixel_num, height);
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

void histogram_equalization(unsigned char *image, long pixel_num, int height) {
	// initialize histogram array and transform array
	if (!CUDA) {
		struct timespec start, stop; 
		double time;
		unsigned char *imgout = (unsigned char *)malloc(pixel_num);

		int counter_array[COLORDEPTH], trans_table[COLORDEPTH];
		
		if( clock_gettime(CLOCK_REALTIME, &start) == -1) { perror("clock gettime");}
			
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
			imgout[i] = trans_table[image[i]];
		}
		if( clock_gettime( CLOCK_REALTIME, &stop) == -1 ) { perror("clock gettime");}   
		time = (stop.tv_sec - start.tv_sec)+ (double)(stop.tv_nsec - start.tv_nsec)/1e9;

		printf("Execution time baseline is = %f sec\n", time);
	}
	else if(CUDA){
		// Timing structures
		struct timespec start, stop; 
		double time;
	
		int block_size = BLOCKSIZE ? height:1;
		unsigned char *rgb_image_g;
		unsigned char *final_image;
		int *counter_array_g;
		int *transformed_histogram;
	
		// declare memory in GPU.
		cudaMalloc((void **)&rgb_image_g, sizeof(unsigned char)*pixel_num);
		cudaMalloc((void **)&final_image, sizeof(unsigned char)*pixel_num);
		cudaMalloc((void **)&counter_array_g, sizeof(int)*COLORDEPTH);
		cudaMalloc((void **)&transformed_histogram, sizeof(int)*COLORDEPTH);

		// Transfer image from host to device
		cudaMemcpy(rgb_image_g, image, sizeof(unsigned char)*pixel_num, cudaMemcpyHostToDevice);
	
		dim3 block(block_size,1);
		dim3 grid(((pixel_num + block_size - 1)/block_size),1);
	
		if( clock_gettime(CLOCK_REALTIME, &start) == -1) { perror("clock gettime");}
		
		// calling kernal to do histogram eq.
		cu_pll_hist_eq<<<grid,block>>>(rgb_image_g, pixel_num, counter_array_g, block_size);
	
		// calling transformation function.
		histogram_transform<<<1, COLORDEPTH>>>(counter_array_g, transformed_histogram, pixel_num);
	
		// calling image transformation function.
		transform_image<<<grid, block>>>(transformed_histogram, final_image, rgb_image_g, pixel_num);

		if( clock_gettime( CLOCK_REALTIME, &stop) == -1 ) { perror("clock gettime");}   
		time = (stop.tv_sec - start.tv_sec)+ (double)(stop.tv_nsec - start.tv_nsec)/1e9;

		printf("Cuda Execution time = %f sec\n", time);
		printf("================================\n");

		// retrieving image from device
		//unsigned char *final_image_host = (unsigned char *)malloc(sizeof(unsigned char)*pixel_num);
		cudaMemcpy(image, final_image, sizeof(unsigned char)*pixel_num, cudaMemcpyDeviceToHost);
		
		cudaFree(rgb_image_g);
		cudaFree(final_image);;
		cudaFree(&counter_array_g);
		cudaFree(&transformed_histogram);
	}
}
