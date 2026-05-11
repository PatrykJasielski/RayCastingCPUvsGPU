#include <iostream>
#include <SDL3/SDL.h>
#include <cmath>
#include <limits>

#define GRID_COLS 10
#define GRID_ROWS 10
#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 800
#define EPS 0.0001f
#define PI 3.141592

const int cellWidth = WINDOW_WIDTH / GRID_COLS;
const int cellHeight = WINDOW_HEIGHT / GRID_ROWS;

class Player {
    public:
        float x;
        float y;
        float fov = PI / 3;
        float angle;
        float moveSpeed;
        float rotationSpeed;
        float sightLength; 

        Player(float x, float y, float angle = 0.0f, float moveSpeed = 200.0f, float rotationSpeed = 1.5f, float sightLength = 1000.0f)
        {
            this->x = x * cellWidth;
            this->y = y * cellHeight;
            this->angle = angle;
            this->moveSpeed = moveSpeed;
            this->rotationSpeed = rotationSpeed;
            this->sightLength = sightLength;
        }

        void update(int map[GRID_ROWS][GRID_COLS], SDL_Scancode input, float deltaTime)
        {
            float moveStep = moveSpeed * deltaTime;
            float rotStep = rotationSpeed * deltaTime;

            if (input == SDL_SCANCODE_W)
            {
                this->x += cos(this->angle) * moveStep;
                this->y += sin(this->angle) * moveStep;
            }

            if (input == SDL_SCANCODE_S)
            {
                this->x -= cos(this->angle) * moveStep;
                this->y -= sin(this->angle) * moveStep;
            }

            if (input == SDL_SCANCODE_A)
            {
                this->angle -= rotStep;
            }

            if (input == SDL_SCANCODE_D)
            {
                this->angle += rotStep;
            }
        }
};

class Vector2 {
    public:
        float x;
        float y;

        Vector2(float x = 0, float y = 0) {
            this->x = x;
            this->y = y;
        }

        Vector2 sub(const Vector2& p2) const
        {
            return Vector2(x - p2.x, y - p2.y);
        }
};

Vector2 pointToCell(const Vector2& p)
{
    return Vector2(p.x / cellWidth, p.y / cellHeight);
}

void drawCircle(SDL_Renderer* renderer, int cx, int cy, int r)
{
    for (int dy = -r; dy <= r; dy++)
    {
        int dx = (int)sqrt(r * r - dy * dy);

        SDL_RenderLine(
            renderer,
            cx - dx, cy + dy,
            cx + dx, cy + dy
        );
    }
}

void grid(SDL_Renderer *renderer)
{
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);

    //Draw Grid

    for (int y = 0; y <= GRID_ROWS; ++y)
    {
        SDL_RenderLine(renderer, 0, y * cellHeight, WINDOW_WIDTH, y * cellHeight);
    }

    for (int x = 0; x <= GRID_COLS; ++x)
    {
        SDL_RenderLine(renderer, x * cellWidth, 0, x * cellWidth, WINDOW_HEIGHT);
    }
}

Vector2 rayStep(Vector2 p1, Vector2 p2)
{
    Vector2 dir = p2.sub(p1);

    float nextX = 0, nextY = 0;
    float tX = std::numeric_limits<float>::infinity();
    float tY = std::numeric_limits<float>::infinity();

    // X intersection
    if (dir.x != 0)
    {
        if (dir.x > 0)
        {
            nextX = floor(p1.x / cellWidth) * cellWidth + cellWidth;
        }
        else
        {
            nextX = floor(p1.x / cellWidth) * cellWidth - EPS;
        }

        tX = (nextX - p1.x) / dir.x;
    }

    // Y intersection
    if (dir.y != 0)
    {
        if (dir.y > 0)
        {
            nextY = floor(p1.y / cellHeight) * cellHeight + cellHeight;
        }
        else
        {
            nextY = floor(p1.y / cellHeight) * cellHeight - EPS;
        }

        tY = (nextY - p1.y) / dir.y;
    }

    Vector2 hit;
    if (tX < tY)
        hit = Vector2(nextX, p1.y + dir.y * tX);
    else
        hit = Vector2(p1.x + dir.x * tY, nextY);

    return hit;
}

void drawWalls(SDL_Renderer* renderer, int map[GRID_ROWS][GRID_COLS])
{
    float x = 0, y = 0;
    for (int i = 0; i < GRID_COLS; i++)
    {
        for (int j = 0; j < GRID_ROWS; j++)
        {
            if (map[j][i] == 1)
            {
                x = i * cellWidth;
                y = j * cellHeight;

                SDL_SetRenderDrawColor(renderer, 40, 90, 100, 255);
                SDL_FRect wall = {x, y, cellWidth, cellHeight};
                SDL_RenderFillRect(renderer, &wall);
            }
        }
    }
}

bool isWallAt(int map[GRID_ROWS][GRID_COLS], Vector2 p)
{
    Vector2 cell = pointToCell(p);
    int cellX = (int)cell.x;
    int cellY = (int)cell.y;

    if (cellX < 0 || cellX >= GRID_COLS || cellY < 0 || cellY >= GRID_ROWS)
        return true;

    if (map[cellY][cellX] == 1)
    {
        return true;
    }
    return false;

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
    
    SDL_Window* window = SDL_CreateWindow("RayCasting", WINDOW_WIDTH, WINDOW_HEIGHT, 0);
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

    bool isRunning = true;

    SDL_Event event;
    
    Player player(3.0f, 3.0f, PI / 2);

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
                switch (event.key.scancode)
                {
                    case SDL_SCANCODE_ESCAPE:
                        isRunning = false;
                        break;
                }
                break;
            }
        }

        // Set BLACK window background
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);

        //Player movement
        const bool* keys = SDL_GetKeyboardState(NULL);

        if (keys[SDL_SCANCODE_W])
            player.update(map, SDL_SCANCODE_W, deltaTime);

        if (keys[SDL_SCANCODE_S])
            player.update(map, SDL_SCANCODE_S, deltaTime);

        if (keys[SDL_SCANCODE_A])
            player.update(map, SDL_SCANCODE_A, deltaTime);

        if (keys[SDL_SCANCODE_D])
            player.update(map, SDL_SCANCODE_D, deltaTime);
        
        grid(renderer);
        drawWalls(renderer, map);

        //draw player
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        drawCircle(renderer, player.x, player.y, 10);


        //Vector2 p2 = Vector2(player.x + cos(player.angle) * player.sightLength, player.y + sin(player.angle) * player.sightLength);

        //Vector2 current = Vector2(player.x, player.y);

        float startAngle = player.angle - (player.fov / 2);
        float endAgnle = player.angle + (player.fov / 2);
        int numberOfRays = 100;

        float angleStep = player.fov / numberOfRays;

        int rayIndex = 0;
        
        //Raycasting
        while (rayIndex < numberOfRays)
        {
            float rayAngle = startAngle + rayIndex * angleStep;

            Vector2 p2(player.x + cos(rayAngle) * player.sightLength, player.y + sin(rayAngle) * player.sightLength);
            Vector2 current = Vector2(player.x, player.y);

            while (true)
            {
                Vector2 prev = current;
                current = rayStep(current, p2);

                if (fabs(current.x - prev.x) < EPS && fabs(current.y - prev.y) < EPS)
                    break;

                drawCircle(renderer, current.x, current.y, 5);

                if (isWallAt(map, current))
                {
                    SDL_RenderLine(renderer, prev.x, prev.y, current.x, current.y);
                    break;
                }

                SDL_RenderLine(renderer, prev.x, prev.y, current.x, current.y);
            }
            rayIndex++;
        }

        fps = 1.0 / deltaTime;
        std::cout << "FPS: " << fps << std::endl;
        SDL_RenderPresent(renderer);
    }

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
