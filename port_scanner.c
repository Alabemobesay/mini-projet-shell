/**
 * port_scanner.c - Scanner de ports réseau multi-thread
 * 
 * Compilation: gcc -o port_scanner port_scanner.c -lpthread
 * Usage: ./port_scanner "port1,port2,port3,..."
 * 
 * Exemple: ./port_scanner "22,80,443,3306"
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/time.h>

#define MAX_PORTS 50
#define TIMEOUT_SEC 2

/**
 * Structure pour passer les données au thread
 */
typedef struct {
    int port;
    int is_open;
} port_info_t;

/**
 * Vérifie si un port est ouvert sur localhost
 */
int check_port(int port) {
    int sockfd;
    struct sockaddr_in server_addr;
    struct timeval timeout;
    
    // Création du socket
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        return 0;
    }
    
    // Configuration du timeout
    timeout.tv_sec = TIMEOUT_SEC;
    timeout.tv_usec = 0;
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    
    // Configuration de l'adresse
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    
    // Tentative de connexion
    int result = connect(sockfd, (struct sockaddr*)&server_addr, sizeof(server_addr));
    close(sockfd);
    
    return (result == 0);
}

/**
 * Fonction exécutée par chaque thread
 */
void* scan_port(void* arg) {
    port_info_t* info = (port_info_t*)arg;
    info->is_open = check_port(info->port);
    return NULL;
}

/**
 * Affichage d'une barre de progression
 */
void show_progress(int current, int total) {
    int percent = (current * 100) / total;
    int bars = percent / 2;
    
    printf("\r  [");
    for (int i = 0; i < 50; i++) {
        if (i < bars) printf("=");
        else if (i == bars) printf(">");
        else printf(" ");
    }
    printf("] %3d%%", percent);
    fflush(stdout);
}

int main(int argc, char* argv[]) {
    // Vérification des arguments
    if (argc != 2) {
        fprintf(stderr, "Usage: %s \"port1,port2,port3,...\"\n", argv[0]);
        fprintf(stderr, "Exemple: %s \"22,80,443,3306,8080\"\n", argv[0]);
        return 1;
    }
    
    printf("\n");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║         SCANNER DE PORTS MULTI-THREAD                ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\n");
    
    // Parsing des ports
    char* ports_str = strdup(argv[1]);
    char* token = strtok(ports_str, ",");
    port_info_t ports[MAX_PORTS];
    int port_count = 0;
    
    printf("  📡 Analyse des ports: ");
    while (token != NULL && port_count < MAX_PORTS) {
        ports[port_count].port = atoi(token);
        printf("%d ", ports[port_count].port);
        port_count++;
        token = strtok(NULL, ",");
    }
    printf("\n\n");
    
    if (port_count == 0) {
        printf("  ❌ Aucun port valide trouvé\n");
        free(ports_str);
        return 1;
    }
    
    // Création des threads
    pthread_t threads[MAX_PORTS];
    
    printf("  🔍 Scan en cours (multi-thread)...\n\n");
    
    for (int i = 0; i < port_count; i++) {
        pthread_create(&threads[i], NULL, scan_port, &ports[i]);
        show_progress(i + 1, port_count);
    }
    
    printf("\n\n");
    
    // Attente de la fin des threads
    for (int i = 0; i < port_count; i++) {
        pthread_join(threads[i], NULL);
    }
    
    // Affichage des résultats
    printf("  ┌─────────────────────────────────────────────────┐\n");
    printf("  │                   RÉSULTATS                     │\n");
    printf("  ├─────────────────────────────────────────────────┤\n");
    
    int open_count = 0;
    for (int i = 0; i < port_count; i++) {
        if (ports[i].is_open) {
            printf("  │  ✅ Port %-5d : OUVERT                           │\n", ports[i].port);
            open_count++;
        } else {
            printf("  │  ❌ Port %-5d : FERMÉ                           │\n", ports[i].port);
        }
    }
    
    printf("  ├─────────────────────────────────────────────────┤\n");
    printf("  │  📊 Total: %d port(s) ouvert(s) sur %d            │\n", open_count, port_count);
    printf("  └─────────────────────────────────────────────────┘\n");
    printf("\n");
    
    free(ports_str);
    return 0;
}