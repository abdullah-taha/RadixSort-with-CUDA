#include <stdio.h>

//predicate function 
/*

test the first bit, returns an arrays of 1's and 0's called predicate
1 indicates that the first bit is zero, 0 indicates that the first bit is 1
and calculate the number of ones in the predicate and store it in dnumOfOnes

inputs :
d_in : input array that which predicate will be calculated (ex: 2, 3, 4, 6, 7, 1)
d_out : output array , result of predicate 			  	   (ex: 1, 0, 1, 1, 0, 0)
*/
__global__ void predicate(int* d_in, int* d_out, int* d_numOfOnes, int bitNo)
{
	if((d_in[threadIdx.x] & bitNo) == bitNo) {d_out[threadIdx.x] = 0;}
	else {d_out[threadIdx.x] = 1;atomicAdd(d_numOfOnes, 1);}
}


//flip_bits function
/*
flips all bit values in the input array (d_in) and store the result in the output array (d_out)
used in calculating the ters_predicate 
*/
__global__ void flip_bits(int *d_in,int *d_out)
{
	int indeks = threadIdx.x;
	d_out[indeks] = !d_in[indeks];
}


// scan function
/*
Blelloch scan : https://www.youtube.com/watch?v=mmYv3Haj6uc
every element in the output list is the sum of all the previous elements 
*/
__global__ void scan(int *d_in, int n)
{
	int indeks = threadIdx.x;
	int i;
	for(i=2; i <= n; i <<= 1)
	{
		
		if((indeks + 1) % i == 0)
		{
			//printf("inside if, indeks is %d \n",indeks);
			int offset = i >> 1;
			//printf("thread %d befor d_in[indeks] = %d offset is %d \n",indeks,d_in[indeks],offset);
			d_in[indeks] += d_in[indeks - offset];
			//printf("thread %d after d_in[indeks] = %d \n",indeks,d_in[indeks]);
		}
	}
	__syncthreads();

	// down sweep
	d_in[n-1] = 0;
	int j;
	for(j= i>>1; j>=2; j>>=1)
	{
		int offset = j >> 1;
		//printf("j is %d \n", j);
		if((indeks+1) % j == 0)
		{
			//printf("indeks is %d",indeks+1);
			int c = d_in[indeks];
			d_in[indeks] += d_in[indeks - offset];
			d_in[indeks - offset] = c; 
		}

	}
}


// sort function 
/*
here where the magic happens , we determine the new indexe for every element according to the followings:
for the i th element in the array, if the predicate is True(1), we move the element to the index in the i th element in the predicate scan array
if the predicate is False , we move the element to the index calculated by , indeks = corresonding value in the ters_predict_scan + numOfones

*/
__global__ void sort(int* d_input_array,int* d_output_array, int* d_predict, int* d_predict_scan, int* d_predict_numOfones, int* d_ters_predict, int* d_ters_predict_scan)
{
	int indeks = threadIdx.x;
	if(d_predict[indeks] == 1)
	{
		int new_indeks = d_predict_scan[indeks];
		d_output_array[new_indeks] = d_input_array[indeks];
	}

	else
	{
		int new_indeks = d_ters_predict_scan[indeks] + *d_predict_numOfones ;
		d_output_array[new_indeks] = d_input_array[indeks];
	}
} 

int main(void)
{


	// defining input array and fill it
	int *h_input_array = (int*)malloc(sizeof(int)*8);
	//for(int i=1;i<11;i++)h_input_array[i-1]=i;
	h_input_array[0]=7;
	h_input_array[1]=25;
	h_input_array[2]=2;
	h_input_array[3]=4;
	h_input_array[4]=70;
	h_input_array[5]=100;
	h_input_array[6]=8;
	h_input_array[7]=7;

	//print the input array
	//printf("array :\n");
	//for(int i=0;i<8;i++)printf("%d, ",h_input_array[i]);
	//printf("\n");

	//allocate memory on the host and device for the final sorted result array
	int* h_result_scan = (int*)malloc(sizeof(int)*8);
	int* d_result_scan;
	cudaMalloc(&d_result_scan, sizeof(int)*8);

	// allocate memory on the host and device for the perdicate ters
	int* h_predicate_ters_result = (int*)malloc(sizeof(int)*8);
	int* d_predicate_ters_result;
	cudaMalloc(&d_predicate_ters_result, sizeof(int)*8);

	//allocate memory on the host and device for the predicate result
	int* h_predicate_result = (int*)malloc(sizeof(int)*8);
	int *d_predicate_result;
	cudaMalloc(&d_predicate_result, sizeof(int)*8);

	//allocate memory on the device for the input array
	int* d_input_array;
	cudaMalloc(&d_input_array, sizeof(int)*8);
	cudaMemcpy(d_input_array, h_input_array,sizeof(int)*8, cudaMemcpyHostToDevice);

	//allocate memory on the device for the number of ones in the predicate result 
	int* d_numOfOnes;
	int* h_numOfOnes = (int*)malloc(sizeof(int));
	cudaMalloc(&d_numOfOnes, sizeof(int));

	//allocate memory on the host for the scan result array
	int* h_ters_predict_scan = (int*)malloc(sizeof(int)*8);
	int* d_result_ters_scan;
	cudaMalloc(&d_result_ters_scan, sizeof(int)*8);

	//allocate memory on host and device for output sorted array
	int* h_sort_result = (int*)malloc(sizeof(int)*8);
	int* d_sort_result;
	cudaMalloc(&d_sort_result, sizeof(int)*8);

// bitmap is a mask to be used in bitwise operations , initial value is 1 to test the first bit
int bitmap = 1;
for(int k=0;k<32;k++)
{
	//print array at every step to watch the sorting
	printf("array :\n");
	for(int i=0;i<8;i++)printf("%d, ",h_input_array[i]);
	printf("\n");

	//set the numOfOnes to 0 at every iteration
	cudaMemset(d_numOfOnes,0,sizeof(int));

	// call the predicate kernel 
	predicate<<<1,8>>>(d_input_array,d_predicate_result,d_numOfOnes,bitmap);

	//copy the predicate result and number of ones from the device to  the host
	cudaMemcpy(h_predicate_result, d_predicate_result,sizeof(int)*8, cudaMemcpyDeviceToHost);
	cudaMemcpy(h_numOfOnes, d_numOfOnes,sizeof(int), cudaMemcpyDeviceToHost);

	// print the predicate array and number of ones
	printf("predicate :\n");
	for(int i=0;i<8;i++)printf(" %d, ",h_predicate_result[i]);
	printf("\n");
	printf("num of ones : %d \n",*h_numOfOnes);

	//copy the predicate result from host to the device and store it in d_result scan. the change will be applied on the same array
	cudaMemcpy(d_result_scan, h_predicate_result,sizeof(int)*8, cudaMemcpyHostToDevice);

	//invoke the kernal function
	scan<<<1,8>>>(d_result_scan,8);

	//copy the result back to the host 
	cudaMemcpy(h_result_scan, d_result_scan,sizeof(int)*8, cudaMemcpyDeviceToHost);

	//print the result
	printf("predicate scan result :\n");
	for(int i=0;i<8;i++)printf(" %d, ",h_result_scan[i]);
	printf("\n");

	//call the flip bits kernel on the device
	flip_bits<<<1,8>>>(d_predicate_result,d_predicate_ters_result);

	//copy the result to the host
	cudaMemcpy(h_predicate_ters_result,d_predicate_ters_result,sizeof(int)*8,cudaMemcpyDeviceToHost);

	//print the result
	printf("predict ters :\n");
	for(int i=0;i<8;i++)printf(" %d, ",h_predicate_ters_result[i]);
	printf("\n");

	//copy the !predicate from the host to the device and store it in d_result_ters_scan
	cudaMemcpy(d_result_ters_scan, h_predicate_ters_result,sizeof(int)*8, cudaMemcpyHostToDevice);

	//call the scan upon d_result_ters_scan, the change will be applied ont he same array
	scan<<<1,8>>>(d_result_ters_scan,8);

	//copy the result to the host h_ters_predicate_scan
	cudaMemcpy(h_ters_predict_scan, d_result_ters_scan,sizeof(int)*8, cudaMemcpyDeviceToHost);

	//print the result
	printf("ters predicate scan result :\n");
	for(int i=0;i<8;i++)printf(" %d, ",h_ters_predict_scan[i]);
	printf("\n");


	//invoke the sorting function on the kernel
	sort<<<1,8>>>(d_input_array, d_sort_result, d_predicate_result, d_result_scan, d_numOfOnes, d_predicate_ters_result, d_result_ters_scan );
	//copy the sorted list back to the host and print it 
	cudaMemcpy(h_sort_result, d_sort_result,sizeof(int)*8, cudaMemcpyDeviceToHost);
	printf("\n\n\n\n\nSORTED WITH CUDA !!!!!!!!!!:\n");
	for(int i=0;i<8;i++)printf(" %d, ",h_sort_result[i]);

	//printf("bitmap %d ",bitmap);

	//update the mask to test the next bit 
	bitmap <<= 1;

	//update the input array for every iteration
	memcpy(h_input_array,h_sort_result, 8 * sizeof(int));
	//update the input array on the device
	cudaMemcpy(d_input_array, h_input_array,sizeof(int)*8, cudaMemcpyHostToDevice);
}

  	cudaFree(d_input_array);
  	cudaFree(d_sort_result);
  	cudaFree(d_result_scan);
  	cudaFree(d_predicate_result);
  	cudaFree(d_numOfOnes);
  	cudaFree(d_predicate_ters_result);
  	cudaFree(d_result_ters_scan);
	return 0;

	
}