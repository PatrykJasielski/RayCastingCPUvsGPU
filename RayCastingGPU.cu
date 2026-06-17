#include <iostream>
#include <SDL3/SDL.h>
#include <cmath>
#include <limits>
#include <cuda_runtime.h>

#define GRID_COLS 10
#define GRID_ROWS 10
#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 800
#define EPS 0.0001f
#define PI 3.141592f

#define MAX_STEPS 512
#define NUMBER_OF_RAYS 100

const int cellWidth = WINDOW_WIDTH / GRID_COLS;
const int cellHeight = WINDOW_HEIGHT / GRID_ROWS;

struct Vector2
{
    float x;
    float y;

    __host__ __device__
        Vector2(float x = 0.0f, float y = 0.0f) : x(x), y(y) {}

    __host__ __device__
        Vector2 sub(const Vector2& p2) const
    {
        return Vector2(x - p2.x, y - p2.y);
    }
};

// Jeden segment trasy promienia (prev → current)
struct RaySegment
{
    Vector2 from;
    Vector2 to;
    bool    isHit;      // czy to ostatni segment (trafienie w ścianę / koniec)
    bool    valid;      // czy segment istnieje
};

// Wynik dla jednego promienia: tablica segmentów + ich liczba
struct RayResult
{
    RaySegment segments[MAX_STEPS];
    int        count;
    Vector2    hitCircle;   // pozycja kółka na każdym kroku (ostatni punkt)
    int        circleCount;
};

class Player
{
public:
    float x;
    float y;
    float fov = PI / 3.0f;
    float angle;
    float moveSpeed;
    float rotationSpeed;
    float sightLength;

    Player(float x, float y, float angle = 0.0f,
        float moveSpeed = 200.0f, float rotationSpeed = 1.5f,
        float sightLength = 1000.0f)
    {
        this->x = x * cellWidth;
        this->y = y * cellHeight;
        this->angle = angle;
        this->moveSpeed = moveSpeed;
        this->rotationSpeed = rotationSpeed;
        this->sightLength = sightLength;
    }

    void update(SDL_Scancode input, float deltaTime)
    {
        float moveStep = moveSpeed * deltaTime;
        float rotStep = rotationSpeed * deltaTime;

        if (input == SDL_SCANCODE_W)
        {
            x += cosf(angle) * moveStep;
            y += sinf(angle) * moveStep;
        }
        if (input == SDL_SCANCODE_S)
        {
            x -= cosf(angle) * moveStep;
            y -= sinf(angle) * moveStep;
        }
        if (input == SDL_SCANCODE_A) angle -= rotStep;
        if (input == SDL_SCANCODE_D) angle += rotStep;
    }
};

__device__
Vector2 pointToCell(const Vector2& p)
{
    return Vector2(p.x / cellWidth, p.y / cellHeight);
}

__device__
bool isWallAt(int* map, Vector2 p)
{
    Vector2 cell = pointToCell(p);
    int     cellX = (int)cell.x;
    int     cellY = (int)cell.y;

    if (cellX < 0 || cellX >= GRID_COLS || cellY < 0 || cellY >= GRID_ROWS)
        return true;

    return map[cellY * GRID_COLS + cellX] == 1;
}

__device__
Vector2 rayStep(Vector2 p1, Vector2 p2)
{
    Vector2 dir = p2.sub(p1);

    float nextX = 0.0f, nextY = 0.0f;
    float tX = 1e30f;
    float tY = 1e30f;

    // Przecięcie z pionowymi liniami siatki
    if (dir.x != 0.0f)
    {
        if (dir.x > 0.0f)
            nextX = floorf(p1.x / cellWidth) * cellWidth + cellWidth;
        else
            nextX = floorf(p1.x / cellWidth) * cellWidth - EPS;

        tX = (nextX - p1.x) / dir.x;
    }

    // Przecięcie z poziomymi liniami siatki
    if (dir.y != 0.0f)
    {
        if (dir.y > 0.0f)
            nextY = floorf(p1.y / cellHeight) * cellHeight + cellHeight;
        else
            nextY = floorf(p1.y / cellHeight) * cellHeight - EPS;

        tY = (nextY - p1.y) / dir.y;
    }

    if (tX < tY)
        return Vector2(nextX, p1.y + dir.y * tX);
    else
        return Vector2(p1.x + dir.x * tY, nextY);
}

__global__
void castRaysKernel(
    int* map,
    float      playerX,
    float      playerY,
    float      playerAngle,
    float      playerFov,
    float      playerSightLength,
    RayResult* results
)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    if (i >= NUMBER_OF_RAYS)
        return;

    float startAngle = playerAngle - (playerFov / 2.0f);
    float angleStep = playerFov / NUMBER_OF_RAYS;
    float rayAngle = startAngle + i * angleStep;

    Vector2 p2(
        playerX + cosf(rayAngle) * playerSightLength,
        playerY + sinf(rayAngle) * playerSightLength
    );

    Vector2 current(playerX, playerY);

    results[i].count = 0;
    results[i].circleCount = 0;

    for (int step = 0; step < MAX_STEPS; step++)
    {
        Vector2 prev = current;
        current = rayStep(current, p2);

        // Zatrzymaj jeśli promień nie przesuwa się (punkt końcowy)
        if (fabsf(current.x - prev.x) < EPS && fabsf(current.y - prev.y) < EPS)
            break;

        // Zapisz punkt kółka
        if (results[i].circleCount < MAX_STEPS)
        {
            results[i].hitCircle = current;
            results[i].circleCount++;
        }

        int idx = results[i].count;
        if (idx < MAX_STEPS)
        {
            results[i].segments[idx].from = prev;
            results[i].segments[idx].to = current;
            results[i].segments[idx].valid = true;

            if (isWallAt(map, current))
            {
                results[i].segments[idx].isHit = true;
                results[i].count = idx + 1;
                break;  // trafiono w ścianę
            }

            results[i].segments[idx].isHit = false;
            results[i].count = idx + 1;
        }
    }
}

void drawCircle(SDL_Renderer* renderer, int cx, int cy, int r)
{
    for (int dy = -r; dy <= r; dy++)
    {
        int dx = (int)sqrtf((float)(r * r - dy * dy));
        SDL_RenderLine(renderer, cx - dx, cy + dy, cx + dx, cy + dy);
    }
}

void grid(SDL_Renderer* renderer)
{
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);

    for (int y = 0; y <= GRID_ROWS; ++y)
        SDL_RenderLine(renderer, 0, y * cellHeight, WINDOW_WIDTH, y * cellHeight);

    for (int x = 0; x <= GRID_COLS; ++x)
        SDL_RenderLine(renderer, x * cellWidth, 0, x * cellWidth, WINDOW_HEIGHT);
}

void drawWalls(SDL_Renderer* renderer, int map[GRID_ROWS][GRID_COLS])
{
    for (int j = 0; j < GRID_ROWS; j++)
    {
        for (int i = 0; i < GRID_COLS; i++)
        {
            if (map[j][i] == 1)
            {
                SDL_SetRenderDrawColor(renderer, 40, 90, 100, 255);
                SDL_FRect wall = {
                    (float)(i * cellWidth),
                    (float)(j * cellHeight),
                    (float)cellWidth,
                    (float)cellHeight
                };
                SDL_RenderFillRect(renderer, &wall);
            }
        }
    }
}

int main()
{
    int map[GRID_ROWS][GRID_COLS] =
    {
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 1, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 1, 0, 0, 0, 0, 0, 1, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 1, 0, 0},
        {0, 0, 0, 0, 0, 0, 1, 1, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    };

    SDL_Init(SDL_INIT_VIDEO);

    SDL_Window* window = SDL_CreateWindow("RayCasting CUDA", WINDOW_WIDTH, WINDOW_HEIGHT, 0);
    if (!window)
    {
        std::cout << "Window error: " << SDL_GetError() << std::endl;
        SDL_Quit();
        return -1;
    }

    SDL_Renderer* renderer = SDL_CreateRenderer(window, NULL);
    if (!renderer)
    {
        std::cout << "Renderer error: " << SDL_GetError() << std::endl;
        SDL_DestroyWindow(window);
        SDL_Quit();
        return -1;
    }

    // Alokacja GPU
    int* d_map;
    cudaMalloc(&d_map, sizeof(int) * GRID_ROWS * GRID_COLS);
    cudaMemcpy(d_map, map, sizeof(int) * GRID_ROWS * GRID_COLS, cudaMemcpyHostToDevice);

    RayResult* d_results;
    cudaMalloc(&d_results, sizeof(RayResult) * NUMBER_OF_RAYS);

    RayResult* h_results = new RayResult[NUMBER_OF_RAYS];

    bool isRunning = true;
    SDL_Event event;

    Player player(3.0f, 3.0f, PI / 2.0f);

    Uint64 lastTime = SDL_GetPerformanceCounter();
    double fps = 0.0;

    while (isRunning)
    {
        Uint64 currentTime = SDL_GetPerformanceCounter();
        Uint64 freq = SDL_GetPerformanceFrequency();
        double deltaTime = (double)(currentTime - lastTime) / freq;
        lastTime = currentTime;

        while (SDL_PollEvent(&event))
        {
            switch (event.type)
            {
            case SDL_EVENT_QUIT:
                isRunning = false;
                break;
            case SDL_EVENT_KEY_DOWN:
                if (event.key.scancode == SDL_SCANCODE_ESCAPE)
                    isRunning = false;
                break;
            }
        }

        // Ruch gracza (identyczny z oryginałem)
        const bool* keys = SDL_GetKeyboardState(NULL);

        if (keys[SDL_SCANCODE_W]) player.update(SDL_SCANCODE_W, (float)deltaTime);
        if (keys[SDL_SCANCODE_S]) player.update(SDL_SCANCODE_S, (float)deltaTime);
        if (keys[SDL_SCANCODE_A]) player.update(SDL_SCANCODE_A, (float)deltaTime);
        if (keys[SDL_SCANCODE_D]) player.update(SDL_SCANCODE_D, (float)deltaTime);

        // ── Raycasting na GPU ──────────────────────
        int threads = 128;
        int blocks = (NUMBER_OF_RAYS + threads - 1) / threads;

        castRaysKernel << <blocks, threads >> > (
            d_map,
            player.x,
            player.y,
            player.angle,
            player.fov,
            player.sightLength,
            d_results
            );

        cudaDeviceSynchronize();

        cudaMemcpy(
            h_results,
            d_results,
            sizeof(RayResult) * NUMBER_OF_RAYS,
            cudaMemcpyDeviceToHost
        );
        // ──────────────────────────────────────────

        // Rysowanie (identyczne z oryginałem)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);

        grid(renderer);
        drawWalls(renderer, map);

        // Gracz
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        drawCircle(renderer, (int)player.x, (int)player.y, 10);

        // Promienie z wyników GPU
        for (int i = 0; i < NUMBER_OF_RAYS; i++)
        {
            const RayResult& ray = h_results[i];

            for (int s = 0; s < ray.count; s++)
            {
                const RaySegment& seg = ray.segments[s];
                if (!seg.valid) continue;

                // Kółka na punktach przecięcia siatki
                drawCircle(renderer, (int)seg.to.x, (int)seg.to.y, 5);

                // Linie promienia
                SDL_RenderLine(
                    renderer,
                    (int)seg.from.x, (int)seg.from.y,
                    (int)seg.to.x, (int)seg.to.y
                );
            }
        }

        fps = 1.0 / deltaTime;
        std::cout << "FPS: " << fps << std::endl;

        SDL_RenderPresent(renderer);
    }

    // Sprzątanie
    delete[] h_results;
    cudaFree(d_results);
    cudaFree(d_map);

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
