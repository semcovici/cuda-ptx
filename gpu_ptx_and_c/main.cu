
#include <vector>
#include <algorithm>
#include <cstdio>
#include <cstdlib>

#define DEBUG_ON
#define LOOP (2)
#define cudaErrChk(ans) { cudaAssert((ans), __FILE__, __LINE__); }
inline void cudaAssert(cudaError_t code, const char *file, int line, bool abort=true);
void check_result(std::vector<int>& A, std::vector<int>& B, std::vector<int>& C);

int M = 1000;
int N = 100;
int K = 100;

/*******************************************************************
  * Kernel code
  ******************************************************************/

#include "include/cuda_c.cuh"
#include "include/cuda_ptx.cuh"






/*******************************************************************
  * Host code
  ******************************************************************/

void measure_basic(const int* d_A, int* d_B, int* d_C, int loop_exe=LOOP) {

    printf("Basic kernel launched...\n");

    // Define que o bloco de threads (que executam em paralelo) tem 16×16=256 threads (bloco bidimensional)
    const dim3 dim_threads(16, 16);

    //Define o grid (grupo de blocos) -> blocos não compartilham dados entre si
    // Calcula o numero de blocos necessarios para "cobrir" as threads acima
    const dim3 dim_blocks(
        (N+dim_threads.x-1)/dim_threads.x, 
        (M+dim_threads.y-1)/dim_threads.y)
        ;
    cudaErrChk( cudaDeviceSynchronize() );

    float gops = 1.0*M*K*N*1e-9*loop_exe;
    float msec_total = 0.0f; // inicializa contador de tempo com 0

    cudaEvent_t start, stop;
    cudaErrChk( cudaEventCreate(&start) );
    cudaErrChk( cudaEventCreate(&stop) );
    cudaErrChk( cudaEventRecord(start, NULL) );
    // Main body - for para executar todas as operacoes definidas
    for (int i=0; i<loop_exe; i++) {
        #ifdef SHARED
        matmul_shared<<<dim_blocks, dim_threads, 2*sizeof(int)*dim_threads.x*dim_threads.x >>>(d_A, d_B, d_C, M, N, K);
        #else
        matmul_basic<<<dim_blocks, dim_threads>>>(d_A, d_B, d_C, M, N, K);
        #endif
    }
    // End of main body
    cudaErrChk( cudaEventRecord(stop, NULL) );
    cudaErrChk( cudaEventSynchronize(stop) );
    cudaErrChk( cudaEventElapsedTime(&msec_total, start, stop) );


        printf(" -- Total number of multiplications : %.3f Gops\n", gops/loop_exe);
        printf(" -- Avg. elapsed time: %.3f s\n", msec_total/loop_exe*1e-3);
        printf(" -- Avg. GILOPS : %.3f\n", (gops/loop_exe)/(msec_total/loop_exe*1e-3));

}

void measure_ptx(const int* d_A, int* d_B, int* d_C, int loop_exe=LOOP) {

    printf("PTX kernel launched...\n");

    const dim3 dim_threads(16, 16);
    const dim3 dim_blocks((N+dim_threads.x-1)/dim_threads.x, (M+dim_threads.y-1)/dim_threads.y);
    cudaErrChk( cudaDeviceSynchronize() );

    float gops = 1.0*M*K*N*1e-9*loop_exe;
    float msec_total = 0.0f;

    cudaEvent_t start, stop;
    cudaErrChk( cudaEventCreate(&start) );
    cudaErrChk( cudaEventCreate(&stop) );
    cudaErrChk( cudaEventRecord(start, NULL) );
    // Main body
    for (int i=0; i<loop_exe; i++) {
        #ifdef SHARED
        matmul_ptx_s32_shared<<<dim_blocks, dim_threads>>>(d_A, d_B, d_C, M, N, K);
        #else
        matmul_ptx_s32_basic<<<dim_blocks, dim_threads>>>(d_A, d_B, d_C, M, N, K);
        #endif
    }
    // End of main body
    cudaErrChk( cudaEventRecord(stop, NULL) );
    cudaErrChk( cudaEventSynchronize(stop) );
    cudaErrChk( cudaEventElapsedTime(&msec_total, start, stop) );

    printf(" -- Total number of multiplications : %.3f Gops\n", gops/loop_exe);
    printf(" -- Avg. elapsed time: %.3f s\n", msec_total/loop_exe*1e-3);
    printf(" -- Avg. GILOPS : %.3f\n", (gops/loop_exe)/(msec_total/loop_exe*1e-3));

}



int init_value() {
    return std::rand() % 10 + 1;
}


int main(void) {

    printf("\n************************************************\n");
    printf("PTX code example - matrix multiplication\n");
    printf(" -- A[%d, %d] * B[%d, %d] = C[%d, %d]\n", M, K, K, N, M, N);
    printf(" -- Total usage of memory : %.3f GB\n", (1.0f*(M*K+K*N+M*N)*sizeof(int))/(1<<30));
    printf("************************************************\n\n");


    /************************************
      * Data Initialization
      ***********************************/

    // Input matrix A
    std::vector<int> A(M*K);
    std::generate(A.begin(), A.end(), init_value);
    // Input matrix B
    std::vector<int> B(K*N);
    std::generate(B.begin(), B.end(), init_value);
    // Input matrix C
    std::vector<int> C(M*N);

    // Alloc GPU memory
    int *d_A, *d_B, *d_C;
    cudaErrChk( cudaMalloc((void**)&d_A, sizeof(int)*M*K) );
    cudaErrChk( cudaMalloc((void**)&d_B, sizeof(int)*K*N) );
    cudaErrChk( cudaMalloc((void**)&d_C, sizeof(int)*M*N) );
    
    // Memcpy from host to device
    cudaErrChk( cudaMemcpy(d_A, A.data(), sizeof(int)*M*K, cudaMemcpyHostToDevice) );
    cudaErrChk( cudaMemcpy(d_B, B.data(), sizeof(int)*K*N, cudaMemcpyHostToDevice) );
    cudaErrChk( cudaDeviceSynchronize() );
    cudaErrChk( cudaGetLastError() );
    
    /************************************
      * Run kernel
      ***********************************/

    // Basic matrix multiplication
    measure_basic(d_A, d_B, d_C);
    #ifdef DEBUG_ON
    cudaErrChk( cudaMemcpy(C.data(), d_C, sizeof(int)*M*N, cudaMemcpyDeviceToHost) );
    cudaErrChk( cudaMemset(d_C, 0, sizeof(int)*M*N) );
    cudaErrChk( cudaDeviceSynchronize() );
    check_result(A, B, C);
    #endif

    // PTX matrix multiplication
    measure_ptx(d_A, d_B, d_C);
    #ifdef DEBUG_ON
    cudaErrChk( cudaMemcpy(C.data(), d_C, sizeof(int)*M*N, cudaMemcpyDeviceToHost) );
    cudaErrChk( cudaDeviceSynchronize() );
    check_result(A, B, C);
    #endif


    /*** Finalize ***/
    cudaErrChk( cudaFree(d_A) );
    cudaErrChk( cudaFree(d_B) );
    cudaErrChk( cudaFree(d_C) );

    return 0;
}




/*******************************************************************
  * Debug code
  ******************************************************************/

inline void cudaAssert(cudaError_t code, const char *file, int line, bool abort) {
   if (code != cudaSuccess) 
   {
      fprintf(stderr,"CUDA assert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}


void check_result(std::vector<int>& A, std::vector<int>& B, std::vector<int>& C) {
    
    printf(" -- Checking result ...\n");
    for (int y=0; y<M; y++) {
        for (int x=0; x<N; x++) {
            int sum = 0;
            for (int k=0; k<K; k++) {
                sum += A[y*K+k]*B[k*N+x];
            }
            if ( C[y*N+x]!= sum) {
                printf(" -- [[ERROR]] Checking result is failed at C[%d, %d](%d) != gt(%d)\n", y, x, C[y*N+x], sum);
                return;
            }
        }
        
    }
    printf(" -- Chekcing result succeed!!\n");

}



